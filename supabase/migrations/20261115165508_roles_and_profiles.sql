-- =============================================================================
-- Golden Maids – Roles, user roles and profiles
-- =============================================================================

-- -----------------------------------------------------------------------------
-- roles: the fixed list of roles. Changed only through migrations.
-- -----------------------------------------------------------------------------
create table public.roles (
  id          text primary key check (id ~ '^[a-z_]+$'),
  name        text not null,
  description text not null default '',
  is_staff    boolean not null default false,
  created_at  timestamptz not null default now()
);

comment on table public.roles is
  'Fixed list of user roles. Managed only through migrations.';

insert into public.roles (id, name, description, is_staff) values
  ('super_admin',         'Super Administrator', 'Full access, including managing administrators.',      true),
  ('admin',               'Administrator',       'Manages the platform, staff roles and all records.',   true),
  ('recruitment_officer', 'Recruitment Officer', 'Manages candidates and hiring requests.',             true),
  ('visa_officer',        'Visa Officer',        'Manages visa applications and documents.',            true),
  ('finance_officer',     'Finance Officer',     'Manages payments, refunds and financial reports.',    true),
  ('booking_manager',     'Booking Manager',     'Manages service bookings, schedules and providers.',  true),
  ('service_provider',    'Service Provider',    'Delivers booked home services.',                      false),
  ('customer',            'Customer',            'Books services and hires domestic workers.',          false);

-- -----------------------------------------------------------------------------
-- profiles: one row per user, created automatically on sign-up.
-- -----------------------------------------------------------------------------
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text check (full_name is null or char_length(full_name) between 1 and 120),
  email       text,
  phone       text,
  -- Storage path of the profile photo (not a public URL).
  avatar_url  text check (avatar_url is null or char_length(avatar_url) <= 500),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.profiles is
  'Customer and staff profiles. email and phone are copied from auth.users and cannot be edited directly.';

create index profiles_email_idx on public.profiles (lower(email));
create index profiles_phone_idx on public.profiles (phone);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function private.set_updated_at();

-- -----------------------------------------------------------------------------
-- user_roles: which user has which role(s).
-- -----------------------------------------------------------------------------
create table public.user_roles (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  role_id     text not null references public.roles (id),
  granted_by  uuid default auth.uid() references public.profiles (id) on delete set null,
  granted_at  timestamptz not null default now(),
  primary key (user_id, role_id)
);

comment on table public.user_roles is
  'Role assignments. Only administrators can grant or remove roles; only super administrators can manage administrator roles.';

create index user_roles_role_id_idx    on public.user_roles (role_id);
create index user_roles_granted_by_idx on public.user_roles (granted_by);

-- -----------------------------------------------------------------------------
-- Role-check helpers used by RLS policies across the whole database.
-- SECURITY DEFINER so they can read user_roles without recursive RLS checks.
-- -----------------------------------------------------------------------------
create or replace function private.has_role(p_role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_roles ur
    where ur.user_id = (select auth.uid())
      and ur.role_id = p_role
  );
$$;

create or replace function private.has_any_role(p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_roles ur
    where ur.user_id = (select auth.uid())
      and ur.role_id = any (p_roles)
  );
$$;

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_any_role(array['super_admin', 'admin']);
$$;

create or replace function private.is_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = (select auth.uid())
      and r.is_staff
  );
$$;

revoke all on function private.has_role(text)       from public, anon;
revoke all on function private.has_any_role(text[]) from public, anon;
revoke all on function private.is_admin()           from public, anon;
revoke all on function private.is_staff()           from public, anon;
grant execute on function private.has_role(text)       to authenticated;
grant execute on function private.has_any_role(text[]) to authenticated;
grant execute on function private.is_admin()           to authenticated;
grant execute on function private.is_staff()           to authenticated;

-- -----------------------------------------------------------------------------
-- Sign-up: create the profile and give the Customer role.
-- -----------------------------------------------------------------------------
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, phone, full_name)
  values (
    new.id,
    new.email,
    new.phone,
    nullif(left(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), 120), '')
  );

  insert into public.user_roles (user_id, role_id, granted_by)
  values (new.id, 'customer', null);

  return new;
end;
$$;

revoke all on function private.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Keep profiles.email / profiles.phone in sync with the verified auth values.
create or replace function private.handle_user_contact_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
  set email = new.email,
      phone = new.phone
  where id = new.id;
  return new;
end;
$$;

revoke all on function private.handle_user_contact_change() from public, anon, authenticated;

create trigger on_auth_user_contact_changed
  after update of email, phone on auth.users
  for each row
  when (old.email is distinct from new.email or old.phone is distinct from new.phone)
  execute function private.handle_user_contact_change();

-- -----------------------------------------------------------------------------
-- Row Level Security
-- -----------------------------------------------------------------------------
alter table public.roles      enable row level security;
alter table public.profiles   enable row level security;
alter table public.user_roles enable row level security;

-- Guests (anon) get no access at all.
revoke all on public.roles, public.profiles, public.user_roles from anon;

-- roles: read-only for signed-in users.
revoke insert, update, delete, truncate on public.roles from authenticated;

create policy "Signed-in users can read roles"
  on public.roles for select
  to authenticated
  using (true);

-- profiles: users see their own; staff see all.
-- Users may edit only full_name and avatar_url on their own profile.
revoke insert, update, delete, truncate on public.profiles from authenticated;
grant update (full_name, avatar_url) on public.profiles to authenticated;

create policy "Users view own profile; staff view all"
  on public.profiles for select
  to authenticated
  using (id = (select auth.uid()) or (select private.is_staff()));

create policy "Users update own profile"
  on public.profiles for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- user_roles: users see their own; admins see all.
-- Admins grant/remove roles; only super admins manage admin roles.
-- Nobody can remove their own roles (prevents accidental lock-out).
revoke update, truncate on public.user_roles from authenticated;

create policy "Users view own roles; admins view all"
  on public.user_roles for select
  to authenticated
  using (user_id = (select auth.uid()) or (select private.is_admin()));

create policy "Admins grant roles"
  on public.user_roles for insert
  to authenticated
  with check (
    (select private.is_admin())
    and granted_by = (select auth.uid())
    and (
      role_id not in ('super_admin', 'admin')
      or (select private.has_role('super_admin'))
    )
  );

create policy "Admins remove roles"
  on public.user_roles for delete
  to authenticated
  using (
    (select private.is_admin())
    and user_id <> (select auth.uid())
    and (
      role_id not in ('super_admin', 'admin')
      or (select private.has_role('super_admin'))
    )
  );
