-- =============================================================================
-- Golden Maids – Account deletion requests, and a fix for deleting addresses
-- =============================================================================
-- Customers ask for their account to be deleted from the app (required by
-- Google Play and the App Store). Administrators process each request: they
-- delete the login and personal data and keep anonymised booking and hiring
-- records. The request row is kept as a record that the deletion was done.

create table public.account_deletion_requests (
  id           uuid primary key default gen_random_uuid(),
  -- Set to null when the account is finally deleted (the record stays).
  user_id      uuid default auth.uid() references public.profiles (id) on delete set null,
  reason       text not null default '' check (char_length(reason) <= 500),
  status       text not null default 'pending'
                 check (status in ('pending', 'completed', 'withdrawn')),
  staff_note   text not null default '' check (char_length(staff_note) <= 1000),
  handled_by   uuid references public.profiles (id) on delete set null,
  handled_at   timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.account_deletion_requests is
  'Customer requests to delete their account; processed by administrators.';

create index account_deletion_requests_user_idx on public.account_deletion_requests (user_id);
create index account_deletion_requests_handled_by_idx on public.account_deletion_requests (handled_by);
create index account_deletion_requests_status_idx on public.account_deletion_requests (status, created_at);
create unique index account_deletion_requests_one_pending
  on public.account_deletion_requests (user_id) where status = 'pending';

create trigger account_deletion_requests_set_updated_at
  before update on public.account_deletion_requests
  for each row execute function private.set_updated_at();

-- Customers may only withdraw their own pending request; administrators record
-- who handled a request and when.
create or replace function private.guard_account_deletion_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select private.is_admin()) then
    if new.status is distinct from old.status and new.status <> 'pending' then
      new.handled_by := (select auth.uid());
      new.handled_at := now();
    end if;
    return new;
  end if;

  if old.status <> 'pending' or new.status <> 'withdrawn'
     or new.reason is distinct from old.reason
     or new.staff_note is distinct from old.staff_note then
    raise exception 'You can only withdraw a pending request.' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_account_deletion_request() from public, anon, authenticated;

create trigger account_deletion_requests_guard_update
  before update on public.account_deletion_requests
  for each row execute function private.guard_account_deletion_request();

-- -----------------------------------------------------------------------------
-- Row Level Security
-- -----------------------------------------------------------------------------
alter table public.account_deletion_requests enable row level security;

revoke all on public.account_deletion_requests from anon, authenticated;
grant select on public.account_deletion_requests to authenticated;
grant insert (reason) on public.account_deletion_requests to authenticated;
grant update (status, staff_note) on public.account_deletion_requests to authenticated;

create policy "Customers view own deletion requests; administrators view all"
  on public.account_deletion_requests for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or (select private.is_admin())
  );

create policy "Customers request deletion of their own account"
  on public.account_deletion_requests for insert
  to authenticated
  with check (user_id = (select auth.uid()) and status = 'pending');

create policy "Customers withdraw own pending request; administrators process"
  on public.account_deletion_requests for update
  to authenticated
  using (
    (user_id = (select auth.uid()) and status = 'pending')
    or (select private.is_admin())
  )
  with check (
    (user_id = (select auth.uid()) and status = 'withdrawn')
    or (select private.is_admin())
  );

-- No delete policy: requests are kept as a record.

-- -----------------------------------------------------------------------------
-- Fix: deleting a saved address unlinks it from past bookings
-- -----------------------------------------------------------------------------
-- bookings.address_id is set to null when its saved address is deleted. That
-- update passes through the booking guard, which used to refuse it for
-- bookings the customer can no longer change (completed, cancelled, or within
-- 24 hours), so the address could not be deleted. A change that only clears
-- address_id is now allowed (customers cannot set address_id themselves).
create or replace function private.guard_booking_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_staff boolean := (select private.is_booking_staff());
  v_cancel_hours integer := (select cancel_hours from public.booking_settings);
begin
  if new.address_id is null and old.address_id is not null
     and (to_jsonb(new) - 'address_id' - 'updated_at')
       = (to_jsonb(old) - 'address_id' - 'updated_at') then
    return new;
  end if;

  if not v_staff then
    if old.status not in ('pending', 'confirmed', 'provider_assigned')
       or now() > old.starts_at - make_interval(hours => v_cancel_hours) then
      raise exception 'This booking can no longer be changed in the app. Please call us on +971 4 323 4393.'
        using errcode = '42501';
    end if;
    if new.assigned_staff_id is distinct from old.assigned_staff_id
       or (new.status <> old.status and new.status <> 'cancelled')
       or (new.status = 'cancelled' and new.starts_at <> old.starts_at) then
      raise exception 'You can only cancel or reschedule this booking.' using errcode = '42501';
    end if;
  end if;

  if new.status = 'cancelled' then
    return new;
  end if;

  if new.starts_at <> old.starts_at then
    if v_staff then
      -- Staff may move a booking anywhere; the staff overlap rule still holds.
      new.ends_at := new.starts_at + (old.ends_at - old.starts_at);
    else
      new := private.check_booking_time(new, old.id);
      -- The agency confirms the new time and assigns staff again.
      new.status := 'pending';
      new.assigned_staff_id := null;
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.guard_booking_update() from public, anon, authenticated;
