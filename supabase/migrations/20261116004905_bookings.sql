-- =============================================================================
-- Golden Maids – Home-service bookings (Phase 3)
--
--   * Services have a booking type: hourly (customer picks 2–8 h and a slot),
--     visit (fixed-length job) or request (preferred time; the agency calls).
--   * Slots follow booking_settings (default 8 am – 8 pm UAE, every day,
--     hourly). The database checks capacity when a booking is made, under a
--     lock, so two customers can never take the last slot.
--   * The agency's own staff (service_staff) are assigned by Booking Managers;
--     a staff member can never be assigned to two overlapping bookings.
--   * Customers cancel or reschedule free until 24 h before the start.
--   * Payment on completion (cash or card); no online payment yet.
-- =============================================================================

create extension if not exists btree_gist with schema extensions;

-- -----------------------------------------------------------------------------
-- Who manages bookings
-- -----------------------------------------------------------------------------
create or replace function private.is_booking_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_any_role(array['super_admin', 'admin', 'booking_manager']);
$$;

revoke all on function private.is_booking_staff() from public, anon;
grant execute on function private.is_booking_staff() to authenticated;

-- -----------------------------------------------------------------------------
-- How each service is booked
-- -----------------------------------------------------------------------------
alter table public.services
  add column booking_type text not null default 'request'
    check (booking_type in ('hourly', 'visit', 'request'));

comment on column public.services.booking_type is
  'hourly: customer picks hours + slot; visit: fixed-length job (duration_minutes, default 4 h); request: preferred time, agency arranges.';

update public.services set booking_type = 'hourly'
where slug in ('home-cleaning', 'hourly-maid', 'daily-maid', 'home-cooking',
               'nanny-at-home', 'babysitting', 'baby-care', 'elderly-care', 'pet-care');
update public.services set booking_type = 'visit'
where slug in ('move-in-cleaning', 'move-out-cleaning', 'deep-cleaning', 'furniture-cleaning');
-- All others (weekly/temporary maid, regular housekeeping, caregiver, nurse,
-- driver, 2-year maid visa) stay 'request'.

-- -----------------------------------------------------------------------------
-- Booking settings (one row; editable by administrators)
-- -----------------------------------------------------------------------------
create table public.booking_settings (
  id                 boolean primary key default true check (id),
  open_time          time    not null default '08:00',
  close_time         time    not null default '20:00',
  -- ISO weekdays (1 = Monday … 7 = Sunday).
  open_days          integer[] not null default '{1,2,3,4,5,6,7}',
  slot_minutes       integer not null default 60 check (slot_minutes in (30, 60, 120)),
  min_hours          integer not null default 2 check (min_hours between 1 and 12),
  max_hours          integer not null default 8 check (max_hours between 1 and 12),
  -- Earliest booking: this many hours from now.
  min_notice_hours   integer not null default 3 check (min_notice_hours between 0 and 72),
  -- Latest booking: this many days ahead.
  window_days        integer not null default 30 check (window_days between 1 and 180),
  -- Free cancel / reschedule until this many hours before the start.
  cancel_hours       integer not null default 24 check (cancel_hours between 0 and 168),
  -- Length of a "visit" when the service has no duration set.
  default_visit_minutes integer not null default 240 check (default_visit_minutes between 30 and 720),
  updated_at         timestamptz not null default now(),
  constraint booking_settings_hours check (close_time > open_time and max_hours >= min_hours),
  constraint booking_settings_days check (open_days <@ '{1,2,3,4,5,6,7}' and cardinality(open_days) > 0)
);

comment on table public.booking_settings is 'Working hours and booking rules (single row).';

insert into public.booking_settings default values;

create trigger booking_settings_set_updated_at
  before update on public.booking_settings
  for each row execute function private.set_updated_at();
create trigger booking_settings_audit
  after insert or update or delete on public.booking_settings
  for each row execute function private.log_admin_change();

-- -----------------------------------------------------------------------------
-- The agency's own staff who do home services
-- -----------------------------------------------------------------------------
create table public.service_staff (
  id                uuid primary key default gen_random_uuid(),
  -- Shown to the customer whose booking she is assigned to, e.g. "Grace K.".
  display_name      text not null check (char_length(display_name) between 1 and 60),
  photo_path        text check (photo_path is null or char_length(photo_path) <= 300),
  years_experience  integer not null default 0 check (years_experience between 0 and 50),
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table public.service_staff is
  'Agency staff who carry out home services. Customers see only the staff assigned to their own bookings.';

create table public.service_staff_private (
  staff_id   uuid primary key references public.service_staff (id) on delete cascade,
  full_name  text not null check (char_length(full_name) between 1 and 120),
  phone      text check (phone is null or char_length(phone) between 6 and 20),
  notes      text not null default '' check (char_length(notes) <= 2000)
);

create table public.service_staff_categories (
  staff_id     uuid not null references public.service_staff (id) on delete cascade,
  category_id  uuid not null references public.service_categories (id) on delete cascade,
  primary key (staff_id, category_id)
);
create index service_staff_categories_category_idx on public.service_staff_categories (category_id);

create trigger service_staff_set_updated_at
  before update on public.service_staff
  for each row execute function private.set_updated_at();
create trigger service_staff_audit
  after insert or update or delete on public.service_staff
  for each row execute function private.log_admin_change();

-- -----------------------------------------------------------------------------
-- Bookings
-- -----------------------------------------------------------------------------
create sequence public.booking_number_seq;

create table public.bookings (
  id                 uuid primary key default gen_random_uuid(),
  reference          text not null unique,
  customer_id        uuid not null default auth.uid() references public.profiles (id) on delete restrict,
  service_id         uuid not null references public.services (id) on delete restrict,
  -- Snapshot at booking time.
  service_name       text not null,
  booking_type       text not null check (booking_type in ('hourly', 'visit', 'request')),
  hours              integer check (hours is null or hours between 1 and 12),
  starts_at          timestamptz not null,
  ends_at            timestamptz not null,
  -- Address snapshot (address_id links a saved address, if one was used).
  address_id         uuid references public.addresses (id) on delete set null,
  emirate            text not null check (emirate in ('Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman',
                       'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah')),
  area               text not null check (char_length(btrim(area)) between 2 and 120),
  building           text not null check (char_length(btrim(building)) between 1 and 120),
  apartment          text not null default '' check (char_length(apartment) <= 40),
  address_notes      text not null default '' check (char_length(address_notes) <= 500),
  instructions       text not null default '' check (char_length(instructions) <= 1000),
  customer_name      text not null check (char_length(btrim(customer_name)) between 2 and 120),
  customer_phone     text not null check (char_length(customer_phone) between 6 and 20),
  -- Estimate from the service price (null = price confirmed by the agency).
  price_estimate     numeric(10, 2) check (price_estimate is null or price_estimate >= 0),
  price_unit         text,
  payment_method     text not null default 'cash' check (payment_method in ('cash', 'card_on_completion')),
  status             text not null default 'pending' check (status in (
                       'pending', 'confirmed', 'provider_assigned', 'on_the_way',
                       'in_progress', 'completed', 'cancelled')),
  assigned_staff_id  uuid references public.service_staff (id) on delete set null,
  cancel_reason      text not null default '' check (char_length(cancel_reason) <= 500),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint bookings_times check (ends_at > starts_at),
  -- A staff member can never be booked twice at the same time.
  constraint bookings_no_staff_overlap exclude using gist (
    assigned_staff_id with =,
    tstzrange(starts_at, ends_at) with &&
  ) where (assigned_staff_id is not null and status <> 'cancelled')
);

comment on table public.bookings is
  'Home-service bookings. Customers see and manage their own (within the cancellation policy); booking staff manage all.';

create index bookings_customer_idx on public.bookings (customer_id, starts_at desc);
create index bookings_time_idx on public.bookings (starts_at) where status <> 'cancelled';
create index bookings_status_idx on public.bookings (status, starts_at);
create index bookings_service_idx on public.bookings (service_id);
create index bookings_staff_idx on public.bookings (assigned_staff_id);
create index bookings_address_idx on public.bookings (address_id);

create trigger bookings_set_updated_at
  before update on public.bookings
  for each row execute function private.set_updated_at();

-- -----------------------------------------------------------------------------
-- Slot rules and capacity
-- -----------------------------------------------------------------------------

-- Whether a booking from p_start to p_end (UAE working hours) is allowed by
-- the settings: open day, aligned to a slot, inside working hours.
create or replace function private.booking_time_allowed(p_start timestamptz, p_end timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    extract(isodow from (p_start at time zone 'Asia/Dubai'))::integer = any (s.open_days)
    and (p_start at time zone 'Asia/Dubai')::time >= s.open_time
    and (p_end at time zone 'Asia/Dubai')::time <= s.close_time
    and (p_start at time zone 'Asia/Dubai')::date = (p_end at time zone 'Asia/Dubai')::date
    and (extract(epoch from (p_start at time zone 'Asia/Dubai')::time - s.open_time)::integer
         % (s.slot_minutes * 60)) = 0
  from public.booking_settings s;
$$;

-- Staff matching: can every booking in p_categories (one category per
-- booking happening at the same moment) get its own active, qualified staff
-- member? Standard augmenting-path matching (sizes are small).
create or replace function private.match_augment(
  p_booking integer,
  p_categories uuid[],
  p_staff uuid[],
  inout match_of integer[],
  inout visited boolean[],
  out matched boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  j integer;
  r record;
begin
  matched := false;
  for j in 1 .. coalesce(array_length(p_staff, 1), 0) loop
    if not coalesce(visited[j], false) and exists (
      select 1 from public.service_staff_categories sc
      where sc.staff_id = p_staff[j] and sc.category_id = p_categories[p_booking]
    ) then
      visited[j] := true;
      if match_of[j] is null then
        match_of[j] := p_booking;
        matched := true;
        return;
      end if;
      select * into r from private.match_augment(match_of[j], p_categories, p_staff, match_of, visited);
      match_of := r.match_of;
      visited := r.visited;
      if r.matched then
        match_of[j] := p_booking;
        matched := true;
        return;
      end if;
    end if;
  end loop;
end;
$$;

create or replace function private.staff_can_cover(p_categories uuid[])
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_staff uuid[] := array(select id from public.service_staff where is_active order by id);
  v_match integer[] := array_fill(null::integer, array[greatest(coalesce(array_length(v_staff, 1), 0), 1)]);
  v_visited boolean[];
  r record;
  i integer;
begin
  if coalesce(array_length(p_categories, 1), 0) > coalesce(array_length(v_staff, 1), 0) then
    return false;
  end if;
  for i in 1 .. coalesce(array_length(p_categories, 1), 0) loop
    v_visited := array_fill(false, array[array_length(v_staff, 1)]);
    select * into r from private.match_augment(i, p_categories, v_staff, v_match, v_visited);
    if not r.matched then
      return false;
    end if;
    v_match := r.match_of;
  end loop;
  return true;
end;
$$;

-- Whether a booking of p_service_id from p_start to p_end can be staffed,
-- together with all other bookings at the same time. Checked at every
-- moment a booking starts inside the period (where the most bookings
-- overlap), so it is exact for any mix of staff skills.
create or replace function private.booking_capacity_ok(
  p_service_id uuid, p_start timestamptz, p_end timestamptz, p_exclude uuid default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_category uuid := (select category_id from public.services where id = p_service_id);
  v_point timestamptz;
  v_categories uuid[];
begin
  for v_point in
    select p_start
    union
    select b.starts_at from public.bookings b
    where b.status <> 'cancelled' and b.booking_type <> 'request'
      and b.id is distinct from p_exclude
      and b.starts_at > p_start and b.starts_at < p_end
  loop
    select array_agg(s.category_id) into v_categories
    from public.bookings b
    join public.services s on s.id = b.service_id
    where b.status <> 'cancelled' and b.booking_type <> 'request'
      and b.id is distinct from p_exclude
      and b.starts_at <= v_point and b.ends_at > v_point;
    if not private.staff_can_cover(coalesce(v_categories, '{}') || v_category) then
      return false;
    end if;
  end loop;
  return true;
end;
$$;

revoke all on function private.match_augment(integer, uuid[], uuid[], integer[], boolean[]) from public, anon, authenticated;
revoke all on function private.staff_can_cover(uuid[]) from public, anon, authenticated;
revoke all on function private.booking_time_allowed(timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function private.booking_capacity_ok(uuid, timestamptz, timestamptz, uuid) from public, anon, authenticated;

-- Checks a (new or moved) booking and fills in the computed fields.
create or replace function private.check_booking_time(p_booking public.bookings, p_exclude uuid)
returns public.bookings
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.booking_settings%rowtype;
  svc public.services%rowtype;
  b public.bookings := p_booking;
begin
  select * into s from public.booking_settings;
  select * into svc from public.services where id = b.service_id;

  if b.booking_type = 'hourly' then
    if b.hours is null or b.hours < s.min_hours or b.hours > s.max_hours then
      raise exception 'Please choose between % and % hours.', s.min_hours, s.max_hours using errcode = '23514';
    end if;
    b.ends_at := b.starts_at + make_interval(hours => b.hours);
  elsif b.booking_type = 'visit' then
    b.hours := null;
    b.ends_at := b.starts_at + make_interval(mins => coalesce(svc.duration_minutes, s.default_visit_minutes));
  else
    b.hours := null;
    b.ends_at := b.starts_at + interval '1 hour';
  end if;

  if b.starts_at < now() + make_interval(hours => s.min_notice_hours) then
    raise exception 'Please choose a time at least % hours from now.', s.min_notice_hours using errcode = '23514';
  end if;
  if b.starts_at > now() + make_interval(days => s.window_days) then
    raise exception 'Bookings can be made up to % days ahead.', s.window_days using errcode = '23514';
  end if;
  if not private.booking_time_allowed(b.starts_at, b.ends_at) then
    raise exception 'This time is outside our working hours. Please choose another slot.' using errcode = '23514';
  end if;

  if b.booking_type <> 'request' then
    -- One booking at a time decides on capacity (no two customers can take
    -- the last free slot).
    perform pg_advisory_xact_lock(hashtext('golden_maids.bookings'));
    if not private.booking_capacity_ok(b.service_id, b.starts_at, b.ends_at, p_exclude) then
      raise exception 'Sorry, this slot has just been taken. Please choose another time.' using errcode = '23514';
    end if;
  end if;
  return b;
end;
$$;

revoke all on function private.check_booking_time(public.bookings, uuid) from public, anon, authenticated;

-- New booking: validation, price estimate, reference.
create or replace function private.prepare_booking()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  svc public.services%rowtype;
begin
  select * into svc from public.services s
  where s.id = new.service_id and s.is_active
    and exists (select 1 from public.service_categories c where c.id = s.category_id and c.is_active);
  if not found then
    raise exception 'This service is not available for booking.' using errcode = '23514';
  end if;

  if new.address_id is not null and not exists (
    select 1 from public.addresses a where a.id = new.address_id and a.user_id = new.customer_id
  ) then
    raise exception 'Please choose one of your saved addresses.' using errcode = '23514';
  end if;

  new.service_name := svc.name;
  new.booking_type := svc.booking_type;
  new := private.check_booking_time(new, null);

  new.price_unit := svc.price_unit;
  new.price_estimate := case
    when svc.base_price is null then null
    when svc.booking_type = 'hourly' and svc.price_unit = 'per_hour' then svc.base_price * new.hours
    else svc.base_price
  end;

  new.customer_name := btrim(new.customer_name);
  new.area := btrim(new.area);
  new.building := btrim(new.building);
  new.reference := 'BK-' || to_char(now(), 'YYYY') || '-'
                   || lpad(nextval('public.booking_number_seq')::text, 6, '0');
  new.status := 'pending';
  new.assigned_staff_id := null;
  new.cancel_reason := '';
  return new;
end;
$$;

revoke all on function private.prepare_booking() from public, anon, authenticated;

create trigger bookings_prepare
  before insert on public.bookings
  for each row execute function private.prepare_booking();

-- Changes: customers may only cancel or reschedule (until 24 h before);
-- booking staff may change anything. Moves are re-checked.
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

create trigger bookings_guard_update
  before update on public.bookings
  for each row execute function private.guard_booking_update();

-- -----------------------------------------------------------------------------
-- Booking timeline
-- -----------------------------------------------------------------------------
create table public.booking_history (
  id                   bigint generated always as identity primary key,
  booking_id           uuid not null references public.bookings (id) on delete cascade,
  status               text not null,
  note                 text not null default '' check (char_length(note) <= 2000),
  is_customer_visible  boolean not null default true,
  created_by           uuid default auth.uid() references public.profiles (id) on delete set null,
  created_at           timestamptz not null default now()
);
create index booking_history_booking_idx on public.booking_history (booking_id, created_at);
create index booking_history_created_by_idx on public.booking_history (created_by);

create or replace function private.record_booking_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_note text := coalesce(current_setting('golden_maids.status_note', true), '');
  v_visible boolean := coalesce(nullif(current_setting('golden_maids.status_note_visible', true), '')::boolean, true);
begin
  if tg_op = 'INSERT' then
    insert into public.booking_history (booking_id, status, created_by)
    values (new.id, new.status, (select auth.uid()));
  elsif new.starts_at is distinct from old.starts_at and new.status <> 'cancelled' then
    insert into public.booking_history (booking_id, status, note, is_customer_visible, created_by)
    values (new.id, new.status,
            btrim(concat_ws(' ', 'Rescheduled to ' ||
              to_char(new.starts_at at time zone 'Asia/Dubai', 'DD Mon YYYY, HH12:MI AM') || '.', v_note)),
            v_visible, (select auth.uid()));
  elsif new.status is distinct from old.status then
    insert into public.booking_history (booking_id, status, note, is_customer_visible, created_by)
    values (new.id, new.status,
            case when new.status = 'cancelled' and v_note = '' then new.cancel_reason else v_note end,
            v_visible, (select auth.uid()));
  end if;
  return new;
end;
$$;

revoke all on function private.record_booking_change() from public, anon, authenticated;

create trigger bookings_history
  after insert or update of status, starts_at on public.bookings
  for each row execute function private.record_booking_change();

-- Staff: change status (with an optional note) or add a note only.
create or replace function public.update_booking_status(
  p_booking_id uuid,
  p_status text,
  p_note text default '',
  p_customer_visible boolean default true
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_note text := btrim(coalesce(p_note, ''));
  v_current text;
begin
  if not (select private.is_booking_staff()) then
    raise exception 'Only booking staff can update bookings.' using errcode = '42501';
  end if;
  if p_status not in ('pending', 'confirmed', 'provider_assigned', 'on_the_way',
                      'in_progress', 'completed', 'cancelled') then
    raise exception 'Unknown status.' using errcode = '23514';
  end if;
  if char_length(v_note) > 2000 then
    raise exception 'Please keep the note under 2000 characters.' using errcode = '23514';
  end if;

  select b.status into v_current from public.bookings b where b.id = p_booking_id;
  if not found then
    raise exception 'This booking no longer exists.' using errcode = 'P0002';
  end if;

  if v_current = p_status then
    if v_note = '' then
      return;
    end if;
    insert into public.booking_history (booking_id, status, note, is_customer_visible)
    values (p_booking_id, p_status, v_note, coalesce(p_customer_visible, true));
    return;
  end if;

  perform set_config('golden_maids.status_note', v_note, true);
  perform set_config('golden_maids.status_note_visible',
                     case when coalesce(p_customer_visible, true) then 'true' else 'false' end, true);
  update public.bookings set status = p_status where id = p_booking_id;
  perform set_config('golden_maids.status_note', '', true);
  perform set_config('golden_maids.status_note_visible', '', true);
end;
$$;

revoke all on function public.update_booking_status(uuid, text, text, boolean) from public, anon;
grant execute on function public.update_booking_status(uuid, text, text, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- Available slots for a service on a day (UAE date), for the booking screen.
-- Returns times only (no booking details), so guests may call it too.
-- -----------------------------------------------------------------------------
create or replace function public.available_slots(p_service_id uuid, p_date date, p_hours integer default null)
returns table (starts_at timestamptz, is_available boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  s public.booking_settings%rowtype;
  svc public.services%rowtype;
  v_length interval;
  v_slot timestamptz;
  v_end timestamptz;
begin
  select * into s from public.booking_settings;
  select * into svc from public.services where id = p_service_id and is_active;
  if not found or not (extract(isodow from p_date)::integer = any (s.open_days)) then
    return;
  end if;

  v_length := case svc.booking_type
    when 'hourly' then make_interval(hours => greatest(coalesce(p_hours, s.min_hours), s.min_hours))
    when 'visit' then make_interval(mins => coalesce(svc.duration_minutes, s.default_visit_minutes))
    else interval '1 hour'
  end;

  v_slot := (p_date + s.open_time) at time zone 'Asia/Dubai';
  loop
    v_end := v_slot + v_length;
    exit when (v_end at time zone 'Asia/Dubai')::time > s.close_time
           or (v_end at time zone 'Asia/Dubai')::date > p_date;
    starts_at := v_slot;
    is_available :=
      v_slot >= now() + make_interval(hours => s.min_notice_hours)
      and v_slot <= now() + make_interval(days => s.window_days)
      and (svc.booking_type = 'request'
           or private.booking_capacity_ok(p_service_id, v_slot, v_end, null));
    return next;
    v_slot := v_slot + make_interval(mins => s.slot_minutes);
  end loop;
end;
$$;

revoke all on function public.available_slots(uuid, date, integer) from public;
grant execute on function public.available_slots(uuid, date, integer) to anon, authenticated;

-- Customers see the staff member assigned to one of their bookings.
create or replace function private.is_assigned_to_my_booking(p_staff_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.bookings b
    where b.assigned_staff_id = p_staff_id and b.customer_id = (select auth.uid())
      and b.status <> 'cancelled'
  );
$$;

revoke all on function private.is_assigned_to_my_booking(uuid) from public, anon;
grant execute on function private.is_assigned_to_my_booking(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Row Level Security and privileges
-- -----------------------------------------------------------------------------
alter table public.booking_settings          enable row level security;
alter table public.service_staff             enable row level security;
alter table public.service_staff_private     enable row level security;
alter table public.service_staff_categories  enable row level security;
alter table public.bookings                  enable row level security;
alter table public.booking_history           enable row level security;

revoke all on public.booking_settings, public.service_staff, public.service_staff_private,
  public.service_staff_categories, public.bookings, public.booking_history
  from anon, authenticated;

-- Settings: everyone reads (the app shows hours and the policy); admins edit.
grant select on public.booking_settings to anon, authenticated;
grant update on public.booking_settings to authenticated;
create policy "Everyone reads booking settings" on public.booking_settings
  for select to anon, authenticated using (true);
create policy "Admins update booking settings" on public.booking_settings
  for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));

-- Staff profiles: booking staff manage; customers see their assigned staff.
grant select on public.service_staff to authenticated;
grant insert, update, delete on public.service_staff to authenticated;
create policy "Booking staff read all staff; customers their assigned staff" on public.service_staff
  for select to authenticated
  using ((select private.is_booking_staff()) or (select private.is_assigned_to_my_booking(id)));
create policy "Booking staff add staff" on public.service_staff
  for insert to authenticated with check ((select private.is_booking_staff()));
create policy "Booking staff update staff" on public.service_staff
  for update to authenticated
  using ((select private.is_booking_staff())) with check ((select private.is_booking_staff()));
create policy "Admins delete staff" on public.service_staff
  for delete to authenticated using ((select private.is_admin()));

grant select, insert, update, delete on public.service_staff_private, public.service_staff_categories to authenticated;
create policy "Booking staff manage staff private details" on public.service_staff_private
  for all to authenticated
  using ((select private.is_booking_staff())) with check ((select private.is_booking_staff()));
create policy "Booking staff manage staff categories" on public.service_staff_categories
  for all to authenticated
  using ((select private.is_booking_staff())) with check ((select private.is_booking_staff()));

-- Bookings: customers create, read, cancel and reschedule their own;
-- booking staff read and update all.
grant select on public.bookings to authenticated;
grant insert (service_id, hours, starts_at, address_id, emirate, area, building, apartment,
              address_notes, instructions, customer_name, customer_phone, payment_method)
  on public.bookings to authenticated;
grant update (status, starts_at, cancel_reason, assigned_staff_id) on public.bookings to authenticated;

create policy "Customers read own bookings; staff read all" on public.bookings
  for select to authenticated
  using (customer_id = (select auth.uid()) or (select private.is_booking_staff()));
create policy "Customers create own bookings" on public.bookings
  for insert to authenticated
  with check (customer_id = (select auth.uid()));
create policy "Customers change own bookings; staff all" on public.bookings
  for update to authenticated
  using (customer_id = (select auth.uid()) or (select private.is_booking_staff()))
  with check (customer_id = (select auth.uid()) or (select private.is_booking_staff()));

grant select on public.booking_history to authenticated;
grant insert (booking_id, status, note, is_customer_visible) on public.booking_history to authenticated;
create policy "Customers read own visible history; staff read all" on public.booking_history
  for select to authenticated
  using (
    (is_customer_visible and exists (
      select 1 from public.bookings b
      where b.id = booking_id and b.customer_id = (select auth.uid())))
    or (select private.is_booking_staff())
  );
create policy "Booking staff add notes" on public.booking_history
  for insert to authenticated with check ((select private.is_booking_staff()));
