-- =============================================================================
-- Golden Maids – Staff notifications (the bell in the staff website)
-- =============================================================================
-- Events from the app are written here automatically by triggers. Each
-- notification belongs to an area; staff see only their areas' notifications:
--   bookings    – Booking Managers and Administrators
--   recruitment – Recruitment Officers and Administrators
--   admin       – Administrators
-- Read status is kept per staff member. New rows are streamed to the website
-- through Supabase Realtime (Row Level Security applies to the stream too).

create table public.staff_notifications (
  id          bigint generated always as identity primary key,
  area        text not null check (area in ('bookings', 'recruitment', 'admin')),
  kind        text not null check (kind ~ '^[a-z_]+\.[a-z_]+$'),
  title       text not null check (char_length(title) between 1 and 160),
  body        text not null default '' check (char_length(body) <= 500),
  -- Staff website page to open, e.g. /bookings/view/?id=…
  link        text check (link is null or link ~ '^/'),
  created_at  timestamptz not null default now()
);

comment on table public.staff_notifications is
  'Notifications for staff about app events; written by triggers, read per area.';

create index staff_notifications_area_created_idx on public.staff_notifications (area, created_at desc);
create index staff_notifications_created_idx on public.staff_notifications (created_at desc);

create table public.staff_notification_reads (
  user_id          uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  notification_id  bigint not null references public.staff_notifications (id) on delete cascade,
  read_at          timestamptz not null default now(),
  primary key (user_id, notification_id)
);

comment on table public.staff_notification_reads is
  'Which staff notifications each staff member has read.';

create index staff_notification_reads_notification_idx on public.staff_notification_reads (notification_id);

-- Whether the signed-in user works in [p_area].
create or replace function private.can_see_staff_area(p_area text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case p_area
    when 'bookings' then private.is_booking_staff()
    when 'recruitment' then private.is_recruitment_staff()
    when 'admin' then private.is_admin()
    else false
  end;
$$;

revoke all on function private.can_see_staff_area(text) from public, anon;
grant execute on function private.can_see_staff_area(text) to authenticated;

-- -----------------------------------------------------------------------------
-- Row Level Security
-- -----------------------------------------------------------------------------
alter table public.staff_notifications enable row level security;
alter table public.staff_notification_reads enable row level security;

revoke all on public.staff_notifications from anon, authenticated;
grant select on public.staff_notifications to authenticated;

revoke all on public.staff_notification_reads from anon, authenticated;
grant select, insert on public.staff_notification_reads to authenticated;

create policy "Staff read their areas' notifications"
  on public.staff_notifications for select
  to authenticated
  using ((select private.can_see_staff_area(area)));

create policy "Staff see what they have read"
  on public.staff_notification_reads for select
  to authenticated
  using (user_id = (select auth.uid()));

create policy "Staff mark their notifications as read"
  on public.staff_notification_reads for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.staff_notifications n
      where n.id = notification_id
        and (select private.can_see_staff_area(n.area))
    )
  );

-- -----------------------------------------------------------------------------
-- Mark as read: given ids, or everything visible (p_ids null)
-- -----------------------------------------------------------------------------
create or replace function public.mark_staff_notifications_read(p_ids bigint[] default null)
returns void
language sql
security invoker
set search_path = ''
as $$
  insert into public.staff_notification_reads (user_id, notification_id)
  select (select auth.uid()), n.id
  from public.staff_notifications n
  where (p_ids is null or n.id = any (p_ids))
  on conflict do nothing;
$$;

revoke all on function public.mark_staff_notifications_read(bigint[]) from public, anon;
grant execute on function public.mark_staff_notifications_read(bigint[]) to authenticated;

-- -----------------------------------------------------------------------------
-- Writing notifications
-- -----------------------------------------------------------------------------
create or replace function private.notify_staff(
  p_area text, p_kind text, p_title text, p_body text, p_link text
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.staff_notifications (area, kind, title, body, link)
  values (p_area, p_kind, left(p_title, 160), left(coalesce(p_body, ''), 500), p_link);
$$;

revoke all on function private.notify_staff(text, text, text, text, text) from public, anon, authenticated;

-- "Fri 20 Nov, 09:00 AM" in UAE time.
create or replace function private.uae_label(p_at timestamptz)
returns text
language sql
stable
set search_path = ''
as $$
  select to_char(p_at at time zone 'Asia/Dubai', 'Dy DD Mon, HH12:MI AM');
$$;

revoke all on function private.uae_label(timestamptz) from public, anon;

-- Bookings: new; cancelled or rescheduled by the customer.
create or replace function private.notify_booking_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_link text := '/bookings/view/?id=' || new.id;
begin
  if tg_op = 'INSERT' then
    perform private.notify_staff('bookings', 'booking.created',
      'New booking ' || new.reference,
      new.service_name || ' · ' || private.uae_label(new.starts_at) || ' · ' || new.customer_name,
      v_link);
  elsif not (select private.is_booking_staff()) then
    if new.status = 'cancelled' and old.status <> 'cancelled' then
      perform private.notify_staff('bookings', 'booking.cancelled',
        'Booking ' || new.reference || ' cancelled by the customer',
        new.service_name || ' · was ' || private.uae_label(old.starts_at)
          || case when new.cancel_reason <> '' then ' · "' || new.cancel_reason || '"' else '' end,
        v_link);
    elsif new.starts_at <> old.starts_at then
      perform private.notify_staff('bookings', 'booking.rescheduled',
        'Booking ' || new.reference || ' rescheduled by the customer',
        new.service_name || ' · now ' || private.uae_label(new.starts_at)
          || ' (was ' || private.uae_label(old.starts_at) || ')',
        v_link);
    end if;
  end if;
  return null;
end;
$$;

revoke all on function private.notify_booking_event() from public, anon, authenticated;

create trigger bookings_notify_staff
  after insert or update of status, starts_at on public.bookings
  for each row execute function private.notify_booking_event();

-- Hiring requests: new; cancelled by the customer.
create or replace function private.notify_hiring_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_link text := '/hiring-requests/view/?id=' || new.id;
  v_package text := (select name from public.recruitment_packages where id = new.package_id);
begin
  if tg_op = 'INSERT' then
    perform private.notify_staff('recruitment', 'hiring.created',
      'New hiring request ' || new.reference,
      coalesce(v_package, 'Hiring request') || ' · ' || new.customer_name || ' · ' || new.emirate,
      v_link);
  elsif new.status = 'cancelled' and old.status <> 'cancelled'
        and not (select private.is_recruitment_staff()) then
    perform private.notify_staff('recruitment', 'hiring.cancelled',
      'Hiring request ' || new.reference || ' cancelled by the customer',
      coalesce(v_package, 'Hiring request') || ' · ' || new.customer_name,
      v_link);
  end if;
  return null;
end;
$$;

revoke all on function private.notify_hiring_event() from public, anon, authenticated;

create trigger hiring_requests_notify_staff
  after insert or update of status on public.hiring_requests
  for each row execute function private.notify_hiring_event();

-- Enquiries ("Request Info"): new.
create or replace function private.notify_enquiry_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.notify_staff('recruitment', 'enquiry.created',
    'New enquiry ' || new.reference,
    new.customer_name || ' about '
      || coalesce((select code from public.candidates where id = new.candidate_id), 'a maid'),
    '/enquiries/view/?id=' || new.id);
  return null;
end;
$$;

revoke all on function private.notify_enquiry_event() from public, anon, authenticated;

create trigger candidate_enquiries_notify_staff
  after insert on public.candidate_enquiries
  for each row execute function private.notify_enquiry_event();

-- Accounts: deletion requested or withdrawn; new sign-up.
create or replace function private.notify_deletion_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_who text := coalesce(
    (select coalesce(nullif(full_name, ''), email, 'A customer') from public.profiles where id = new.user_id),
    'A customer');
begin
  if tg_op = 'INSERT' then
    perform private.notify_staff('admin', 'account.deletion_requested',
      'Account deletion requested',
      v_who || case when new.reason <> '' then ' · "' || new.reason || '"' else '' end,
      '/account-deletions/view/?id=' || new.id);
  elsif new.status = 'withdrawn' and old.status = 'pending' then
    perform private.notify_staff('admin', 'account.deletion_withdrawn',
      'Account deletion request withdrawn',
      v_who || ' kept their account.',
      '/account-deletions/view/?id=' || new.id);
  end if;
  return null;
end;
$$;

revoke all on function private.notify_deletion_event() from public, anon, authenticated;

create trigger account_deletion_requests_notify_staff
  after insert or update of status on public.account_deletion_requests
  for each row execute function private.notify_deletion_event();

create or replace function private.notify_signup_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.notify_staff('admin', 'account.signed_up',
    'New customer signed up',
    coalesce(nullif(new.full_name, ''), 'No name') || coalesce(' · ' || new.email, ''),
    null);
  return null;
end;
$$;

revoke all on function private.notify_signup_event() from public, anon, authenticated;

create trigger profiles_notify_staff
  after insert on public.profiles
  for each row execute function private.notify_signup_event();

-- -----------------------------------------------------------------------------
-- Live updates in the staff website
-- -----------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.staff_notifications;
  end if;
end;
$$;
