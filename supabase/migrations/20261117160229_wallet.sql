-- =============================================================================
-- Golden Maids – Wallet (balance, history, saved cards) – before the gateway
-- =============================================================================
-- * wallet_transactions: one row per money movement the customer sees:
--     top_up      card → wallet balance            (+ balance)
--     payment     for a booking / hiring request    (− balance when paid from
--                 the wallet; 0 when paid by card or cash)
--     refund      back to the wallet (+) or to the card (0)
--     credit      given by the agency               (+ balance)
--     adjustment  correction by an administrator    (+ or −)
--   The balance is the sum of balance_effect over completed rows; a check
--   keeps balance_effect consistent with kind/method, and the balance can
--   never go below zero.
-- * Customers only READ their own rows. Card payments, top-ups and card
--   refunds will be written by the payment gateway's server-side handler
--   (later), never by the app. Administrators can add credits and
--   adjustments from the staff website; the customer is notified.
-- * saved_cards: what the gateway returns after the customer saves a card
--   in the gateway's own secure form (brand, last 4 digits, expiry and the
--   gateway's token). Card numbers are NEVER stored. The token is not
--   readable from the app. Customers can remove a card and choose a default.
-- * Switches (app_settings, public): payments.cards_enabled and
--   wallet.top_up_enabled, both OFF. Top-ups must stay off until the agency
--   confirms stored-value top-ups are allowed (Central Bank of the UAE /
--   licensed partner).
-- * Account deletion: refused while the wallet still holds money.

-- -----------------------------------------------------------------------------
-- Switches
-- -----------------------------------------------------------------------------
insert into public.app_settings (key, value, description, is_public) values
  ('payments.cards_enabled', 'false'::jsonb,
   'Card payments in the app (turn on only when the payment gateway is connected).', true),
  ('wallet.top_up_enabled', 'false'::jsonb,
   'Wallet top-ups (turn on only after the agency confirms stored-value top-ups are allowed).', true)
on conflict (key) do nothing;

-- -----------------------------------------------------------------------------
-- Transactions
-- -----------------------------------------------------------------------------
create sequence public.wallet_transaction_number_seq;

create table public.wallet_transactions (
  id                 uuid primary key default gen_random_uuid(),
  reference          text not null unique,
  -- Kept (without the customer) if the account is deleted, for the accounts.
  customer_id        uuid references public.profiles (id) on delete set null,
  kind               text not null check (kind in ('top_up', 'payment', 'refund', 'credit', 'adjustment')),
  method             text not null check (method in ('card', 'wallet', 'cash', 'agency')),
  amount             numeric(10, 2) not null check (amount > 0 and amount <= 100000),
  balance_effect     numeric(10, 2) not null,
  status             text not null default 'completed'
                       check (status in ('pending', 'completed', 'failed', 'cancelled')),
  description        text not null default '' check (char_length(description) <= 200),
  booking_id         uuid references public.bookings (id) on delete set null,
  hiring_request_id  uuid references public.hiring_requests (id) on delete set null,
  card_brand         text check (card_brand is null or card_brand in ('visa', 'mastercard', 'amex', 'other')),
  card_last4         text check (card_last4 is null or card_last4 ~ '^[0-9]{4}$'),
  gateway_reference  text unique check (gateway_reference is null or char_length(gateway_reference) <= 200),
  created_by         uuid references public.profiles (id) on delete set null,
  created_at         timestamptz not null default now(),
  constraint wallet_transactions_effect_check check (
    (kind in ('top_up', 'credit') and balance_effect = amount)
    or (kind = 'payment' and (
         (method = 'wallet' and balance_effect = -amount)
         or (method <> 'wallet' and balance_effect = 0)))
    or (kind = 'refund' and (
         (method = 'wallet' and balance_effect = amount)
         or (method <> 'wallet' and balance_effect = 0)))
    or (kind = 'adjustment' and method = 'agency' and abs(balance_effect) = amount)
  )
);

comment on table public.wallet_transactions is
  'Wallet balance movements and payment history; written by the payment gateway handler or administrators.';

create index wallet_transactions_customer_idx on public.wallet_transactions (customer_id, created_at desc);
create index wallet_transactions_booking_idx on public.wallet_transactions (booking_id);
create index wallet_transactions_hiring_idx on public.wallet_transactions (hiring_request_id);
create index wallet_transactions_created_by_idx on public.wallet_transactions (created_by);

-- Reference, author, and the balance never below zero.
create or replace function private.prepare_wallet_transaction()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_balance numeric(10, 2);
begin
  new.reference := 'WT-' || to_char(now(), 'YYYY') || '-'
                   || lpad(nextval('public.wallet_transaction_number_seq')::text, 6, '0');
  new.created_by := (select auth.uid());
  new.created_at := now();
  if new.customer_id is null then
    raise exception 'Choose the customer.' using errcode = '23514';
  end if;
  if new.balance_effect < 0 and new.status = 'completed' then
    -- Serialise changes to one customer's balance.
    perform pg_advisory_xact_lock(hashtext('wallet:' || new.customer_id::text));
    select coalesce(sum(t.balance_effect), 0) into v_balance
    from public.wallet_transactions t
    where t.customer_id = new.customer_id and t.status = 'completed';
    if v_balance + new.balance_effect < 0 then
      raise exception 'Not enough wallet balance (AED %).', v_balance using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.prepare_wallet_transaction() from public, anon, authenticated;

create trigger wallet_transactions_prepare
  before insert on public.wallet_transactions
  for each row execute function private.prepare_wallet_transaction();

-- History is permanent: only the gateway handler (server) changes a status.
create or replace function private.guard_wallet_transaction_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Wallet history cannot be changed or deleted.' using errcode = '42501';
end;
$$;

revoke all on function private.guard_wallet_transaction_change() from public, anon, authenticated;

create trigger wallet_transactions_no_change
  before update or delete on public.wallet_transactions
  for each row
  when (current_user in ('authenticated', 'anon'))
  execute function private.guard_wallet_transaction_change();

alter table public.wallet_transactions enable row level security;

revoke all on public.wallet_transactions from anon, authenticated;
grant select (id, reference, customer_id, kind, method, amount, balance_effect, status, description,
              booking_id, hiring_request_id, card_brand, card_last4, created_at)
  on public.wallet_transactions to authenticated;
grant insert (customer_id, kind, method, amount, balance_effect, description)
  on public.wallet_transactions to authenticated;

create policy "Customers read their wallet; admins read all"
  on public.wallet_transactions for select to authenticated
  using (customer_id = (select auth.uid()) or (select private.is_admin()));

create policy "Admins add credits and adjustments"
  on public.wallet_transactions for insert to authenticated
  with check ((select private.is_admin())
              and kind in ('credit', 'adjustment') and method = 'agency'
              and status = 'completed'
              and customer_id is distinct from (select auth.uid()));

create trigger wallet_transactions_audit
  after insert on public.wallet_transactions
  for each row execute function private.log_admin_change();

-- The signed-in customer's balance (completed rows only).
create or replace function public.my_wallet_balance()
returns numeric
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(sum(t.balance_effect), 0)::numeric(10, 2)
  from public.wallet_transactions t
  where t.customer_id = (select auth.uid()) and t.status = 'completed';
$$;

revoke all on function public.my_wallet_balance() from public, anon;
grant execute on function public.my_wallet_balance() to authenticated;

-- Customers hear about credits and corrections.
create or replace function private.notify_wallet_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.kind = 'credit' then
    perform private.notify_customer(new.customer_id, 'wallet.credit',
      'Credit added to your wallet',
      'AED ' || to_char(new.amount, 'FM999,990.00') || ' was added to your wallet'
        || case when new.description <> '' then ': ' || new.description else '.' end);
  elsif new.kind = 'adjustment' then
    perform private.notify_customer(new.customer_id, 'wallet.adjustment',
      'Wallet balance updated',
      'Your wallet was ' || case when new.balance_effect > 0 then 'credited' else 'debited' end
        || ' AED ' || to_char(new.amount, 'FM999,990.00')
        || case when new.description <> '' then ': ' || new.description else '.' end);
  end if;
  return null;
end;
$$;

revoke all on function private.notify_wallet_change() from public, anon, authenticated;

create trigger wallet_transactions_notify
  after insert on public.wallet_transactions
  for each row execute function private.notify_wallet_change();

-- -----------------------------------------------------------------------------
-- Saved cards (from the gateway; never card numbers)
-- -----------------------------------------------------------------------------
create table public.saved_cards (
  id             uuid primary key default gen_random_uuid(),
  customer_id    uuid not null references public.profiles (id) on delete cascade,
  brand          text not null check (brand in ('visa', 'mastercard', 'amex', 'other')),
  last4          text not null check (last4 ~ '^[0-9]{4}$'),
  exp_month      smallint not null check (exp_month between 1 and 12),
  exp_year       smallint not null check (exp_year between 2024 and 2100),
  -- The gateway's reference for the card; not readable from the app.
  gateway_token  text not null unique check (char_length(gateway_token) <= 300),
  is_default     boolean not null default false,
  created_at     timestamptz not null default now()
);

comment on table public.saved_cards is
  'Cards saved through the payment gateway: brand, last 4 digits, expiry and the gateway token only.';

create unique index saved_cards_one_default_idx on public.saved_cards (customer_id) where is_default;
create index saved_cards_customer_idx on public.saved_cards (customer_id);

alter table public.saved_cards enable row level security;

revoke all on public.saved_cards from anon, authenticated;
grant select (id, customer_id, brand, last4, exp_month, exp_year, is_default, created_at)
  on public.saved_cards to authenticated;
grant delete on public.saved_cards to authenticated;

create policy "Customers read their cards"
  on public.saved_cards for select to authenticated
  using (customer_id = (select auth.uid()));

create policy "Customers remove their cards"
  on public.saved_cards for delete to authenticated
  using (customer_id = (select auth.uid()));

-- Choose the default card (one per customer).
create or replace function private.set_default_card(p_card uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if not exists (select 1 from public.saved_cards c where c.id = p_card and c.customer_id = v_uid) then
    raise exception 'Card not found.' using errcode = 'P0002';
  end if;
  update public.saved_cards set is_default = false where customer_id = v_uid and is_default;
  update public.saved_cards set is_default = true where id = p_card;
end;
$$;

revoke all on function private.set_default_card(uuid) from public, anon, authenticated;
grant execute on function private.set_default_card(uuid) to authenticated;

create or replace function public.set_default_card(p_card uuid)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.set_default_card(p_card);
$$;

revoke all on function public.set_default_card(uuid) from public, anon;
grant execute on function public.set_default_card(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Account deletion waits until the wallet is empty
-- -----------------------------------------------------------------------------
create or replace function private.guard_deletion_wallet()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_balance numeric(10, 2);
begin
  if new.status = 'completed' and old.status <> 'completed' then
    select coalesce(sum(t.balance_effect), 0) into v_balance
    from public.wallet_transactions t
    where t.customer_id = new.user_id and t.status = 'completed';
    if v_balance > 0 then
      raise exception 'The customer still has AED % in their wallet. Refund it first.', v_balance
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.guard_deletion_wallet() from public, anon, authenticated;

create trigger account_deletion_requests_wallet_guard
  before update of status on public.account_deletion_requests
  for each row execute function private.guard_deletion_wallet();
