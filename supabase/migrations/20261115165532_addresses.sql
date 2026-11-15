-- =============================================================================
-- Golden Maids – Saved customer addresses
-- =============================================================================

create table public.addresses (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  label         text not null default 'Home' check (char_length(label) between 1 and 40),
  -- ISO country code, ready for GCC expansion.
  country_code  text not null default 'AE' check (country_code ~ '^[A-Z]{2}$'),
  -- Emirate (UAE) or region/province (other GCC countries).
  region        text not null check (char_length(region) between 1 and 80),
  area          text not null check (char_length(area) between 1 and 120),
  street        text check (street is null or char_length(street) <= 160),
  building      text not null check (char_length(building) between 1 and 120),
  apartment     text check (apartment is null or char_length(apartment) <= 40),
  instructions  text check (instructions is null or char_length(instructions) <= 500),
  latitude      double precision check (latitude between -90 and 90),
  longitude     double precision check (longitude between -180 and 180),
  is_default    boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint addresses_uae_emirate check (
    country_code <> 'AE'
    or region in ('Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman',
                  'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah')
  ),
  constraint addresses_coordinates_pair check (
    (latitude is null) = (longitude is null)
  )
);

comment on table public.addresses is
  'Saved service addresses. Each customer has at most one default address.';

create index addresses_user_id_idx on public.addresses (user_id);
create unique index addresses_one_default_per_user
  on public.addresses (user_id) where is_default;

create trigger addresses_set_updated_at
  before update on public.addresses
  for each row execute function private.set_updated_at();

-- When an address becomes the default, the user's previous default is cleared.
-- Runs with the caller's rights, so RLS still applies.
create or replace function private.clear_other_default_addresses()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.is_default then
    update public.addresses
    set is_default = false
    where user_id = new.user_id
      and id <> new.id
      and is_default;
  end if;
  return new;
end;
$$;

revoke all on function private.clear_other_default_addresses() from public, anon;
grant execute on function private.clear_other_default_addresses() to authenticated;

create trigger addresses_single_default
  before insert or update of is_default on public.addresses
  for each row execute function private.clear_other_default_addresses();

-- -----------------------------------------------------------------------------
-- Row Level Security
-- -----------------------------------------------------------------------------
alter table public.addresses enable row level security;

revoke all on public.addresses from anon;
revoke truncate on public.addresses from authenticated;

create policy "Users view own addresses; booking staff view all"
  on public.addresses for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.has_any_role(array['super_admin', 'admin', 'booking_manager']))
  );

create policy "Users add own addresses"
  on public.addresses for insert
  to authenticated
  with check (user_id = (select auth.uid()));

create policy "Users update own addresses"
  on public.addresses for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "Users delete own addresses"
  on public.addresses for delete
  to authenticated
  using (user_id = (select auth.uid()));
