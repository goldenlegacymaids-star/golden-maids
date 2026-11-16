-- =============================================================================
-- Golden Maids – Customer notifications (the bell on the app's Home screen)
-- =============================================================================
-- Written automatically by triggers when the agency changes something the
-- customer should know about:
--   bookings – status changes, reschedules, notes marked visible to the customer
--   hiring   – status changes, notes marked visible to the customer
--   enquiry  – the agency starts handling or closes a "Request Info" enquiry
-- A customer is never notified about their own actions (e.g. cancelling their
-- own booking). Internal notes (not visible to the customer) never appear.
-- Customers read only their own notifications and can only mark them as read.
-- New rows are streamed to the app through Supabase Realtime (Row Level
-- Security applies to the stream too). Push alerts to the phone come later.

create table public.customer_notifications (
  id                 bigint generated always as identity primary key,
  customer_id        uuid not null references public.profiles (id) on delete cascade,
  kind               text not null check (kind ~ '^[a-z_]+\.[a-z_]+$'),
  title              text not null check (char_length(title) between 1 and 160),
  body               text not null default '' check (char_length(body) <= 500),
  -- What a tap opens (at most one is set).
  booking_id         uuid references public.bookings (id) on delete cascade,
  hiring_request_id  uuid references public.hiring_requests (id) on delete cascade,
  candidate_id       uuid references public.candidates (id) on delete set null,
  read_at            timestamptz,
  created_at         timestamptz not null default now()
);

comment on table public.customer_notifications is
  'In-app notifications for customers about agency updates; written by triggers.';

create index customer_notifications_customer_idx on public.customer_notifications (customer_id, created_at desc);
create index customer_notifications_unread_idx on public.customer_notifications (customer_id) where read_at is null;
create index customer_notifications_booking_idx on public.customer_notifications (booking_id);
create index customer_notifications_hiring_idx on public.customer_notifications (hiring_request_id);
create index customer_notifications_candidate_idx on public.customer_notifications (candidate_id);

-- -----------------------------------------------------------------------------
-- Row Level Security: own rows only; the only change allowed is read_at.
-- -----------------------------------------------------------------------------
alter table public.customer_notifications enable row level security;

revoke all on public.customer_notifications from anon, authenticated;
grant select on public.customer_notifications to authenticated;
grant update (read_at) on public.customer_notifications to authenticated;

create policy "Customers read their notifications"
  on public.customer_notifications for select
  to authenticated
  using (customer_id = (select auth.uid()));

create policy "Customers mark their notifications as read"
  on public.customer_notifications for update
  to authenticated
  using (customer_id = (select auth.uid()))
  with check (customer_id = (select auth.uid()));

-- Mark as read: given ids, or all of the customer's (p_ids null).
create or replace function public.mark_customer_notifications_read(p_ids bigint[] default null)
returns void
language sql
security invoker
set search_path = ''
as $$
  update public.customer_notifications
  set read_at = now()
  where customer_id = (select auth.uid())
    and read_at is null
    and (p_ids is null or id = any (p_ids));
$$;

revoke all on function public.mark_customer_notifications_read(bigint[]) from public, anon;
grant execute on function public.mark_customer_notifications_read(bigint[]) to authenticated;

-- -----------------------------------------------------------------------------
-- Writing notifications
-- -----------------------------------------------------------------------------
create or replace function private.notify_customer(
  p_customer uuid, p_kind text, p_title text, p_body text,
  p_booking uuid default null, p_hiring uuid default null, p_candidate uuid default null
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.customer_notifications
    (customer_id, kind, title, body, booking_id, hiring_request_id, candidate_id)
  select p_customer, p_kind, left(p_title, 160), left(coalesce(p_body, ''), 500),
         p_booking, p_hiring, p_candidate
  where p_customer is not null;
$$;

revoke all on function private.notify_customer(uuid, text, text, text, uuid, uuid, uuid)
  from public, anon, authenticated;

-- Bookings: from the booking timeline. A row inserted by the status trigger
-- (trigger depth > 1) is a status change or a reschedule; a row inserted
-- directly by staff is a note.
create or replace function private.notify_customer_booking()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  b public.bookings;
  v_previous text;
  v_when text;
  v_note text := case when new.is_customer_visible then btrim(new.note) else '' end;
  v_title text;
  v_body text;
  v_kind text;
begin
  select * into b from public.bookings where id = new.booking_id;
  if not found or b.customer_id is null or new.created_by is not distinct from b.customer_id then
    return null;
  end if;
  v_when := private.uae_label(b.starts_at);

  if pg_trigger_depth() = 1 then
    -- A note added by staff without a status change.
    if v_note = '' then
      return null;
    end if;
    perform private.notify_customer(b.customer_id, 'booking.note',
      'Message about booking ' || b.reference, v_note, p_booking => b.id);
    return null;
  end if;

  select h.status into v_previous
  from public.booking_history h
  where h.booking_id = new.booking_id and h.id < new.id
  order by h.id desc
  limit 1;
  if v_previous is null then
    return null;  -- the booking was just created
  end if;

  if v_previous = new.status then
    -- Same status: rescheduled. The note starts with "Rescheduled to …".
    v_kind := 'booking.rescheduled';
    v_title := 'Booking rescheduled';
    v_body := 'Your ' || b.service_name || ' is now on ' || v_when || '.';
    -- Keep only the staff's own words after the automatic first sentence.
    v_note := case when new.is_customer_visible
                   then btrim(regexp_replace(new.note, '^Rescheduled to [^.]*\.', ''))
                   else '' end;
  else
    v_kind := 'booking.' || new.status;
    case new.status
      when 'confirmed' then
        v_title := 'Booking confirmed';
        v_body := 'Your ' || b.service_name || ' on ' || v_when || ' is confirmed.';
      when 'provider_assigned' then
        v_title := 'Professional assigned';
        v_body := 'A professional has been assigned to your ' || b.service_name || ' on ' || v_when || '.';
      when 'on_the_way' then
        v_title := 'Your professional is on the way';
        v_body := 'For your ' || b.service_name || ' (' || b.reference || ').';
      when 'in_progress' then
        v_title := 'Your service has started';
        v_body := b.service_name || ' (' || b.reference || ') is in progress.';
      when 'completed' then
        v_title := 'Booking completed';
        v_body := 'Your ' || b.service_name || ' (' || b.reference || ') is complete. Thank you for choosing Golden Maids.';
      when 'cancelled' then
        v_title := 'Booking cancelled';
        v_body := 'The agency cancelled your ' || b.service_name || ' on ' || v_when || '.';
      else
        v_title := 'Booking updated';
        v_body := 'Your ' || b.service_name || ' on ' || v_when || ' is waiting for confirmation again.';
    end case;
  end if;

  if v_note <> '' then
    v_body := v_body || ' ' || v_note;
  end if;
  perform private.notify_customer(b.customer_id, v_kind, v_title, v_body, p_booking => b.id);
  return null;
end;
$$;

revoke all on function private.notify_customer_booking() from public, anon, authenticated;

create trigger booking_history_notify_customer
  after insert on public.booking_history
  for each row execute function private.notify_customer_booking();

-- Hiring requests: from the request timeline (same rule as bookings).
create or replace function private.notify_customer_hiring()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.hiring_requests;
  v_previous text;
  v_note text := case when new.is_customer_visible then btrim(new.note) else '' end;
  v_title text;
  v_body text;
begin
  select * into r from public.hiring_requests where id = new.request_id;
  if not found or r.customer_id is null or new.created_by is not distinct from r.customer_id then
    return null;
  end if;

  if pg_trigger_depth() = 1 then
    if v_note = '' then
      return null;
    end if;
    perform private.notify_customer(r.customer_id, 'hiring.note',
      'Message about request ' || r.reference, v_note, p_hiring => r.id);
    return null;
  end if;

  select h.status into v_previous
  from public.hiring_request_history h
  where h.request_id = new.request_id and h.id < new.id
  order by h.id desc
  limit 1;
  if v_previous is null or v_previous = new.status then
    return null;
  end if;

  case new.status
    when 'under_review' then
      v_title := 'Request under review';
      v_body := 'We''re reviewing your hiring request ' || r.reference || '.';
    when 'shortlisted' then
      v_title := 'Maids shortlisted';
      v_body := 'We''ve shortlisted maids for your request ' || r.reference || '. We''ll contact you about the next step.';
    when 'interview_scheduled' then
      v_title := 'Interview scheduled';
      v_body := 'An interview has been scheduled for your request ' || r.reference || '. We''ll contact you with the details.';
    when 'offer_accepted' then
      v_title := 'Offer accepted';
      v_body := 'The offer for your request ' || r.reference || ' has been accepted.';
    when 'visa_processing' then
      v_title := 'Visa processing started';
      v_body := 'We''ve started the visa process for your request ' || r.reference || '.';
    when 'completed' then
      v_title := 'Hiring completed';
      v_body := 'Your request ' || r.reference || ' is complete. Thank you for choosing Golden Maids.';
    when 'cancelled' then
      v_title := 'Request cancelled';
      v_body := 'The agency cancelled your hiring request ' || r.reference || '.';
    when 'rejected' then
      v_title := 'Request not accepted';
      v_body := 'We couldn''t accept your hiring request ' || r.reference || '. Please contact us for other options.';
    else
      v_title := 'Request updated';
      v_body := 'Your hiring request ' || r.reference || ' has been updated.';
  end case;

  if v_note <> '' then
    v_body := v_body || ' ' || v_note;
  end if;
  perform private.notify_customer(r.customer_id, 'hiring.' || new.status, v_title, v_body, p_hiring => r.id);
  return null;
end;
$$;

revoke all on function private.notify_customer_hiring() from public, anon, authenticated;

create trigger hiring_request_history_notify_customer
  after insert on public.hiring_request_history
  for each row execute function private.notify_customer_hiring();

-- Enquiries ("Request Info"): the agency starts handling or closes one.
create or replace function private.notify_customer_enquiry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_maid text;
begin
  if new.status = old.status or new.status = 'new'
     or (select auth.uid()) is not distinct from new.customer_id then
    return null;
  end if;
  select coalesce(nullif(c.display_name, ''), c.code) into v_maid
  from public.candidates c where c.id = new.candidate_id;
  v_maid := coalesce(v_maid, 'a maid');

  if new.status = 'in_progress' then
    perform private.notify_customer(new.customer_id, 'enquiry.in_progress',
      'We''re on your enquiry',
      'The agency is looking into your enquiry about ' || v_maid || ' (' || new.reference || '). We''ll contact you soon.',
      p_candidate => new.candidate_id);
  else
    perform private.notify_customer(new.customer_id, 'enquiry.closed',
      'Enquiry closed',
      'Your enquiry about ' || v_maid || ' (' || new.reference || ') has been closed. Contact us if you need anything else.',
      p_candidate => new.candidate_id);
  end if;
  return null;
end;
$$;

revoke all on function private.notify_customer_enquiry() from public, anon, authenticated;

create trigger candidate_enquiries_notify_customer
  after update of status on public.candidate_enquiries
  for each row execute function private.notify_customer_enquiry();

-- -----------------------------------------------------------------------------
-- Live updates in the app
-- -----------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.customer_notifications;
  end if;
end;
$$;
