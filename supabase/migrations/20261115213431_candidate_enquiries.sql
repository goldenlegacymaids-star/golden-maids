-- =============================================================================
-- Golden Maids – Candidate enquiries ("Request Info" on a candidate profile)
--
--   * Signed-in customers send an enquiry about a live candidate and see only
--     their own enquiries. They cannot change or delete them afterwards.
--   * Recruitment staff read all enquiries and update status / handler.
--   * At most 5 enquiries per customer per hour (spam protection).
-- =============================================================================

create sequence public.candidate_enquiry_number_seq;

create table public.candidate_enquiries (
  id              uuid primary key default gen_random_uuid(),
  reference       text not null unique,
  customer_id     uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  candidate_id    uuid not null references public.candidates (id) on delete cascade,
  -- Snapshot of the customer's details when the enquiry was sent.
  customer_name   text not null check (char_length(btrim(customer_name)) between 2 and 120),
  customer_phone  text not null check (char_length(customer_phone) between 6 and 20),
  customer_email  text check (customer_email is null or char_length(customer_email) <= 254),
  message         text not null check (char_length(btrim(message)) between 1 and 1000),
  contact_method  text not null default 'phone' check (contact_method in ('phone', 'whatsapp', 'email')),
  status          text not null default 'new' check (status in ('new', 'in_progress', 'closed')),
  handled_by      uuid references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on table public.candidate_enquiries is
  'Customer questions about a candidate ("Request Info"). Customers see their own; recruitment staff manage all.';

create index candidate_enquiries_customer_idx on public.candidate_enquiries (customer_id, created_at desc);
create index candidate_enquiries_candidate_idx on public.candidate_enquiries (candidate_id);
create index candidate_enquiries_status_idx on public.candidate_enquiries (status, created_at desc);
create index candidate_enquiries_handled_by_idx on public.candidate_enquiries (handled_by);

create trigger candidate_enquiries_set_updated_at
  before update on public.candidate_enquiries
  for each row execute function private.set_updated_at();

-- Validation, rate limit and reference number on submission.
create or replace function private.prepare_candidate_enquiry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (select private.is_live_candidate(new.candidate_id)) then
    raise exception 'This candidate is no longer listed.' using errcode = '23514';
  end if;

  if (
    select count(*) from public.candidate_enquiries e
    where e.customer_id = new.customer_id
      and e.created_at > now() - interval '1 hour'
  ) >= 5 then
    raise exception 'You have sent several enquiries recently. Please try again in an hour, or call us.'
      using errcode = '23514';
  end if;

  new.customer_name := btrim(new.customer_name);
  new.message := btrim(new.message);
  new.reference := 'EQ-' || to_char(now(), 'YYYY') || '-'
                   || lpad(nextval('public.candidate_enquiry_number_seq')::text, 6, '0');
  new.status := 'new';
  new.handled_by := null;
  return new;
end;
$$;

revoke all on function private.prepare_candidate_enquiry() from public, anon, authenticated;

create trigger candidate_enquiries_prepare
  before insert on public.candidate_enquiries
  for each row execute function private.prepare_candidate_enquiry();

-- -----------------------------------------------------------------------------
-- Row Level Security and privileges
-- -----------------------------------------------------------------------------
alter table public.candidate_enquiries enable row level security;
revoke all on public.candidate_enquiries from anon, authenticated;

grant select on public.candidate_enquiries to authenticated;
-- customer_id is not insertable: it always defaults to the signed-in user.
grant insert (candidate_id, customer_name, customer_phone, customer_email, message, contact_method)
  on public.candidate_enquiries to authenticated;
grant update (status, handled_by) on public.candidate_enquiries to authenticated;

create policy "Customers read own enquiries; staff read all" on public.candidate_enquiries
  for select to authenticated
  using (customer_id = (select auth.uid()) or (select private.is_recruitment_staff()));
create policy "Customers send own enquiries" on public.candidate_enquiries
  for insert to authenticated
  with check (customer_id = (select auth.uid()));
create policy "Staff update enquiries" on public.candidate_enquiries
  for update to authenticated
  using ((select private.is_recruitment_staff()))
  with check ((select private.is_recruitment_staff()));
