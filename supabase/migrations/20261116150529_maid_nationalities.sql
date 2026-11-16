-- =============================================================================
-- Golden Maids – Maid nationalities (managed list) and prices per nationality
-- =============================================================================
-- Nationalities become a list administrators manage (add, rename, order,
-- hide), each with its ISO country code for the flag. A package can be priced
-- per nationality (the 2-Year GCC Sponsor package: a one-off recruitment
-- cost that depends on the maid's nationality). Hiring requests keep the
-- nationality and the price quoted when they were sent.

-- -----------------------------------------------------------------------------
-- Nationalities
-- -----------------------------------------------------------------------------
create table public.maid_nationalities (
  -- The name is the key, so existing candidates keep their value.
  name        text primary key check (char_length(btrim(name)) between 2 and 60),
  -- ISO 3166-1 alpha-2, e.g. KE; used for the flag.
  code        text not null unique check (code ~ '^[A-Z]{2}$'),
  sort_order  integer not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.maid_nationalities is
  'Nationalities of domestic workers, managed by administrators; code = ISO country code for the flag.';

create trigger maid_nationalities_set_updated_at
  before update on public.maid_nationalities
  for each row execute function private.set_updated_at();

create trigger maid_nationalities_audit
  after insert or update or delete on public.maid_nationalities
  for each row execute function private.log_admin_change();

insert into public.maid_nationalities (name, code, sort_order) values
  ('Kenya',       'KE', 10),
  ('Ethiopia',    'ET', 20),
  ('Myanmar',     'MM', 30),
  ('Indonesia',   'ID', 40),
  ('Philippines', 'PH', 50),
  ('Madagascar',  'MG', 60);

-- Candidates now refer to the list (renames follow automatically).
alter table public.candidates drop constraint candidates_nationality_check;
alter table public.candidates
  add constraint candidates_nationality_fkey
  foreign key (nationality) references public.maid_nationalities (name)
  on update cascade on delete restrict;

-- -----------------------------------------------------------------------------
-- Prices per nationality
-- -----------------------------------------------------------------------------
alter table public.recruitment_packages
  add column price_by_nationality boolean not null default false;

comment on column public.recruitment_packages.price_by_nationality is
  'When true, the price comes from recruitment_package_prices for the maid''s nationality (no price = on request).';

-- The 2-Year GCC Sponsor package: one-off recruitment cost per nationality.
update public.recruitment_packages
set price_by_nationality = true, price_unit = 'total'
where slug = 'two-year-gcc-sponsor';

create table public.recruitment_package_prices (
  package_id   uuid not null references public.recruitment_packages (id) on delete cascade,
  nationality  text not null references public.maid_nationalities (name)
                 on update cascade on delete cascade,
  price        numeric(10, 2) not null check (price >= 0),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (package_id, nationality)
);

comment on table public.recruitment_package_prices is
  'Package prices per maid nationality (packages with price_by_nationality).';

create index recruitment_package_prices_nationality_idx on public.recruitment_package_prices (nationality);

create trigger recruitment_package_prices_set_updated_at
  before update on public.recruitment_package_prices
  for each row execute function private.set_updated_at();

create trigger recruitment_package_prices_audit
  after insert or update or delete on public.recruitment_package_prices
  for each row execute function private.log_admin_change();

-- -----------------------------------------------------------------------------
-- Row Level Security
-- -----------------------------------------------------------------------------
alter table public.maid_nationalities enable row level security;
alter table public.recruitment_package_prices enable row level security;

revoke all on public.maid_nationalities, public.recruitment_package_prices from anon, authenticated;
grant select on public.maid_nationalities, public.recruitment_package_prices to anon, authenticated;
grant insert, update, delete on public.maid_nationalities, public.recruitment_package_prices to authenticated;

create policy "Guests read active nationalities"
  on public.maid_nationalities for select to anon
  using (is_active);

create policy "Users read active nationalities; staff read all"
  on public.maid_nationalities for select to authenticated
  using (is_active or (select private.is_recruitment_staff()));

create policy "Admins add nationalities"
  on public.maid_nationalities for insert to authenticated
  with check ((select private.is_admin()));

create policy "Admins update nationalities"
  on public.maid_nationalities for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy "Admins delete nationalities"
  on public.maid_nationalities for delete to authenticated
  using ((select private.is_admin()));

create policy "Everyone reads package prices"
  on public.recruitment_package_prices for select to anon, authenticated
  using (true);

create policy "Admins add package prices"
  on public.recruitment_package_prices for insert to authenticated
  with check ((select private.is_admin()));

create policy "Admins update package prices"
  on public.recruitment_package_prices for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy "Admins delete package prices"
  on public.recruitment_package_prices for delete to authenticated
  using ((select private.is_admin()));

-- -----------------------------------------------------------------------------
-- Hiring requests keep the nationality and the quoted price
-- -----------------------------------------------------------------------------
alter table public.hiring_requests
  add column preferred_nationality text references public.maid_nationalities (name)
    on update cascade on delete restrict,
  add column quoted_price numeric(10, 2) check (quoted_price is null or quoted_price >= 0),
  add column quoted_price_unit text check (quoted_price_unit is null or quoted_price_unit in ('per_month', 'total'));

comment on column public.hiring_requests.preferred_nationality is
  'The chosen maid''s nationality, or the nationality the customer asked for when the agency recommends.';
comment on column public.hiring_requests.quoted_price is
  'Price shown to the customer when the request was sent (null = on request).';

create index hiring_requests_nationality_idx on public.hiring_requests (preferred_nationality);

grant insert (preferred_nationality) on public.hiring_requests to authenticated;

create or replace function private.prepare_hiring_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_package public.recruitment_packages%rowtype;
  v_candidate_nationality text;
begin
  select * into v_package from public.recruitment_packages
  where id = new.package_id and is_active;
  if not found then
    raise exception 'This package is not available.' using errcode = '23514';
  end if;

  if new.duration_months < v_package.min_months
     or new.duration_months > v_package.max_months
     or (new.duration_months - v_package.min_months) % v_package.month_step <> 0 then
    raise exception 'The selected duration is not available for this package.'
      using errcode = '23514';
  end if;

  if v_package.requires_sponsor_nationality and new.sponsor_nationality is null then
    raise exception 'Please select the sponsor''s GCC nationality.' using errcode = '23514';
  end if;
  if not v_package.requires_sponsor_nationality then
    new.sponsor_nationality := null;
  end if;

  if new.candidate_id is not null then
    select c.nationality into v_candidate_nationality
    from public.candidates c
    where c.id = new.candidate_id and c.is_published and c.archived_at is null
      and c.availability_status = 'available';
    if not found then
      raise exception 'This worker is no longer available.' using errcode = '23514';
    end if;
    -- The chosen maid decides the nationality.
    new.preferred_nationality := v_candidate_nationality;
  elsif v_package.price_by_nationality then
    if new.preferred_nationality is null or not exists (
      select 1 from public.maid_nationalities n
      where n.name = new.preferred_nationality and n.is_active
    ) then
      raise exception 'Please choose the maid''s nationality.' using errcode = '23514';
    end if;
  elsif new.preferred_nationality is not null and not exists (
    select 1 from public.maid_nationalities n
    where n.name = new.preferred_nationality and n.is_active
  ) then
    new.preferred_nationality := null;
  end if;

  -- The price the customer saw (never taken from the app).
  if v_package.price_by_nationality then
    new.quoted_price := (
      select p.price from public.recruitment_package_prices p
      where p.package_id = v_package.id and p.nationality = new.preferred_nationality
    );
  else
    new.quoted_price := v_package.price;
  end if;
  new.quoted_price_unit := case when new.quoted_price is null then null else v_package.price_unit end;

  new.reference := 'HR-' || to_char(now(), 'YYYY') || '-'
                   || lpad(nextval('public.hiring_request_number_seq')::text, 6, '0');
  new.status := 'submitted';
  new.assigned_officer_id := null;
  return new;
end;
$$;

revoke all on function private.prepare_hiring_request() from public, anon, authenticated;
