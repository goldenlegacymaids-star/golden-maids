-- =============================================================================
-- Golden Maids – Visa applications
-- -----------------------------------------------------------------------------
-- One visa application per hiring request, with a step tracker that recruitment
-- staff move forward, visa documents staff upload for the customer (private
-- bucket), and a reminder 7 days before the visa expires.
--
--   Routes and steps (fixed order):
--     abroad      contract_signed → entry_permit → flight_booked → arrived →
--                 medical_test → biometrics → residence_visa → emirates_id
--     in_country  contract_signed → status_change → medical_test →
--                 biometrics → residence_visa → emirates_id
--
-- Customers only read their own; recruitment staff manage all. Applications
-- start when a request moves to "visa_processing", or earlier from the staff
-- website. Dates are only what staff enter: nothing is estimated.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table public.visa_applications (
  id                   uuid primary key default gen_random_uuid(),
  hiring_request_id    uuid not null unique
                         references public.hiring_requests (id) on delete cascade,
  route                text not null check (route in ('abroad', 'in_country')),
  visa_expires_on      date,
  -- The expiry date a reminder was sent for (a new date gets a new reminder).
  expiry_reminded_for  date,
  created_by           uuid references public.profiles (id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

comment on table public.visa_applications is
  'Visa tracker for a hiring request. Customers read their own; recruitment staff manage all.';

create index visa_applications_expiry_idx on public.visa_applications (visa_expires_on)
  where visa_expires_on is not null;
create index visa_applications_created_by_idx on public.visa_applications (created_by);

create trigger visa_applications_set_updated_at
  before update on public.visa_applications
  for each row execute function private.set_updated_at();

create table public.visa_application_steps (
  application_id  uuid not null references public.visa_applications (id) on delete cascade,
  step            text not null check (step in (
                    'contract_signed', 'entry_permit', 'flight_booked', 'arrived',
                    'status_change', 'medical_test', 'biometrics', 'residence_visa',
                    'emirates_id')),
  position        smallint not null check (position between 1 and 20),
  status          text not null default 'waiting'
                    check (status in ('waiting', 'in_progress', 'done')),
  step_date       date,
  note            text not null default '' check (char_length(note) <= 300),
  updated_by      uuid references public.profiles (id) on delete set null,
  updated_at      timestamptz not null default now(),
  primary key (application_id, step)
);

comment on table public.visa_application_steps is
  'The steps of a visa application, in order; staff set each step''s status, date and note.';

create index visa_application_steps_updated_by_idx on public.visa_application_steps (updated_by);

create table public.visa_documents (
  id              uuid primary key default gen_random_uuid(),
  application_id  uuid not null references public.visa_applications (id) on delete cascade,
  document_type   text not null check (document_type in (
                    'visa', 'entry_permit', 'contract', 'ticket', 'medical_booking',
                    'biometrics_booking', 'emirates_id', 'other')),
  title           text not null default '' check (char_length(title) <= 120),
  -- visa-documents/<application id>/<file>
  storage_path    text not null unique check (char_length(storage_path) <= 300),
  file_name       text not null check (char_length(file_name) between 1 and 200),
  mime_type       text not null check (mime_type in ('application/pdf', 'image/jpeg', 'image/png')),
  size_bytes      integer not null check (size_bytes between 1 and 10485760),
  uploaded_by     uuid references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now()
);

comment on table public.visa_documents is
  'Visa documents staff upload for the customer (visa, contract, tickets, bookings, Emirates ID); files in the private visa-documents bucket.';

create index visa_documents_application_idx on public.visa_documents (application_id, created_at);
create index visa_documents_uploaded_by_idx on public.visa_documents (uploaded_by);

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function private.visa_route_steps(p_route text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case p_route
    when 'abroad' then array['contract_signed', 'entry_permit', 'flight_booked', 'arrived',
                             'medical_test', 'biometrics', 'residence_visa', 'emirates_id']
    when 'in_country' then array['contract_signed', 'status_change', 'medical_test',
                                 'biometrics', 'residence_visa', 'emirates_id']
  end;
$$;

create or replace function private.visa_step_label(p_step text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_step
    when 'contract_signed' then 'Contract signed'
    when 'entry_permit' then 'Entry permit'
    when 'flight_booked' then 'Flight booked'
    when 'arrived' then 'Arrival in the UAE'
    when 'status_change' then 'Visa status change'
    when 'medical_test' then 'Medical fitness test'
    when 'biometrics' then 'Emirates ID biometrics'
    when 'residence_visa' then 'Residence visa'
    when 'emirates_id' then 'Emirates ID'
    else p_step end;
$$;

create or replace function private.visa_document_label(p_type text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_type
    when 'visa' then 'Visa'
    when 'entry_permit' then 'Entry permit'
    when 'contract' then 'Contract'
    when 'ticket' then 'Flight ticket'
    when 'medical_booking' then 'Medical test booking'
    when 'biometrics_booking' then 'Biometrics booking'
    when 'emirates_id' then 'Emirates ID'
    else 'Document' end;
$$;

-- Whether the signed-in customer owns this application (by id, as text so
-- storage policies can pass a folder name).
create or replace function private.owns_visa_application(p_application text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.visa_applications a
    join public.hiring_requests h on h.id = a.hiring_request_id
    where a.id::text = p_application
      and h.customer_id = (select auth.uid())
  );
$$;

revoke all on function private.visa_route_steps(text) from public, anon, authenticated;
revoke all on function private.visa_step_label(text) from public, anon, authenticated;
revoke all on function private.visa_document_label(text) from public, anon, authenticated;
revoke all on function private.owns_visa_application(text) from public, anon;
grant execute on function private.owns_visa_application(text) to authenticated;

-- -----------------------------------------------------------------------------
-- Starting an application (staff, or automatically at "visa_processing")
-- -----------------------------------------------------------------------------
-- Returns the application id. Starting again returns the existing one; a new
-- route is only accepted while no step has started.
create or replace function private.start_visa_application(p_request uuid, p_route text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.hiring_requests;
  v_route text;
  v_id uuid;
begin
  if not (select private.is_recruitment_staff()) then
    raise exception 'Only the agency can start a visa application.' using errcode = '42501';
  end if;
  select * into v_request from public.hiring_requests where id = p_request;
  if not found then
    raise exception 'Hiring request not found.' using errcode = 'P0002';
  end if;
  if v_request.status in ('cancelled', 'rejected') then
    raise exception 'This hiring request is closed.' using errcode = '23514';
  end if;
  if p_route is not null and p_route not in ('abroad', 'in_country') then
    raise exception 'Choose From abroad or In the UAE.' using errcode = '23514';
  end if;
  v_route := coalesce(p_route,
    case when v_request.maid_location = 'in_uae' then 'in_country' else 'abroad' end);

  select id into v_id from public.visa_applications where hiring_request_id = p_request;
  if v_id is null then
    insert into public.visa_applications (hiring_request_id, route, created_by)
    values (p_request, v_route, (select auth.uid()))
    returning id into v_id;
  elsif p_route is not null then
    update public.visa_applications set route = p_route where id = v_id;
  end if;
  return v_id;
end;
$$;

revoke all on function private.start_visa_application(uuid, text) from public, anon;
grant execute on function private.start_visa_application(uuid, text) to authenticated;

create or replace function public.start_visa_application(p_request uuid, p_route text default null)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.start_visa_application(p_request, p_route);
$$;

revoke all on function public.start_visa_application(uuid, text) from public, anon;
grant execute on function public.start_visa_application(uuid, text) to authenticated;

comment on function public.start_visa_application(uuid, text) is
  'Recruitment staff: start (or change the route of) the visa application for a hiring request.';

-- Steps follow the route: created with the application, rebuilt when the route
-- changes (only allowed before any step has started).
create or replace function private.guard_visa_application()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.hiring_request_id <> old.hiring_request_id then
    raise exception 'An application cannot move to another request.' using errcode = '42501';
  end if;
  if new.route <> old.route and exists (
       select 1 from public.visa_application_steps
       where application_id = old.id and status <> 'waiting') then
    raise exception 'The route cannot change once a step has started.' using errcode = '23514';
  end if;
  if new.visa_expires_on is distinct from old.visa_expires_on then
    new.expiry_reminded_for := null;
  end if;
  return new;
end;
$$;

revoke all on function private.guard_visa_application() from public, anon, authenticated;

create trigger visa_applications_guard
  before update on public.visa_applications
  for each row execute function private.guard_visa_application();

create or replace function private.build_visa_steps()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer uuid;
begin
  if tg_op = 'UPDATE' and new.route = old.route then
    return null;
  end if;
  delete from public.visa_application_steps where application_id = new.id;
  insert into public.visa_application_steps (application_id, step, position)
  select new.id, s.step, s.position
  from unnest(private.visa_route_steps(new.route)) with ordinality as s(step, position);

  if tg_op = 'INSERT' then
    select customer_id into v_customer from public.hiring_requests where id = new.hiring_request_id;
    perform private.notify_customer(v_customer, 'visa.started', 'Visa application started',
      'We have started the visa process. You can follow each step in My Visa Applications.',
      p_hiring => new.hiring_request_id);
  end if;
  return null;
end;
$$;

revoke all on function private.build_visa_steps() from public, anon, authenticated;

create trigger visa_applications_build_steps
  after insert or update of route on public.visa_applications
  for each row execute function private.build_visa_steps();

-- A request moving to "visa_processing" starts its application.
create or replace function private.start_visa_on_processing()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'visa_processing' and old.status <> 'visa_processing'
     and not exists (select 1 from public.visa_applications where hiring_request_id = new.id) then
    insert into public.visa_applications (hiring_request_id, route, created_by)
    values (new.id,
            case when new.maid_location = 'in_uae' then 'in_country' else 'abroad' end,
            (select auth.uid()));
  end if;
  return null;
end;
$$;

revoke all on function private.start_visa_on_processing() from public, anon, authenticated;

create trigger hiring_requests_start_visa
  after update of status on public.hiring_requests
  for each row execute function private.start_visa_on_processing();

-- -----------------------------------------------------------------------------
-- Steps: staff set status, date and note; the customer is told
-- -----------------------------------------------------------------------------
create or replace function private.guard_visa_step()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.application_id <> old.application_id or new.step <> old.step
     or new.position <> old.position then
    raise exception 'Steps cannot be moved.' using errcode = '42501';
  end if;
  new.note := btrim(new.note);
  -- A finished step without a date gets today's date (UAE).
  if new.status = 'done' and new.step_date is null then
    new.step_date := (now() at time zone 'Asia/Dubai')::date;
  end if;
  if new.status is distinct from old.status or new.step_date is distinct from old.step_date
     or new.note is distinct from old.note then
    new.updated_by := (select auth.uid());
    new.updated_at := now();
  end if;
  return new;
end;
$$;

revoke all on function private.guard_visa_step() from public, anon, authenticated;

create trigger visa_application_steps_guard
  before update on public.visa_application_steps
  for each row execute function private.guard_visa_step();

create or replace function private.notify_visa_step()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request uuid;
  v_customer uuid;
  v_body text;
begin
  if new.status = old.status or new.status = 'waiting' then
    return null;
  end if;
  select a.hiring_request_id, h.customer_id into v_request, v_customer
  from public.visa_applications a
  join public.hiring_requests h on h.id = a.hiring_request_id
  where a.id = new.application_id;

  v_body := private.visa_step_label(new.step)
    || case new.status when 'done' then ': done.' else ': in progress.' end
    || case when new.note <> '' then ' ' || new.note else '' end;
  perform private.notify_customer(v_customer, 'visa.step', 'Visa update', v_body,
    p_hiring => v_request);
  return null;
end;
$$;

revoke all on function private.notify_visa_step() from public, anon, authenticated;

create trigger visa_application_steps_notify
  after update of status on public.visa_application_steps
  for each row execute function private.notify_visa_step();

-- -----------------------------------------------------------------------------
-- Documents: staff upload and remove; the customer reads and is told
-- -----------------------------------------------------------------------------
create or replace function private.guard_visa_document()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if split_part(new.storage_path, '/', 1) <> new.application_id::text then
    raise exception 'This file is not in the application''s folder.' using errcode = '42501';
  end if;
  new.title := btrim(new.title);
  new.uploaded_by := (select auth.uid());
  new.created_at := now();
  return new;
end;
$$;

revoke all on function private.guard_visa_document() from public, anon, authenticated;

create trigger visa_documents_guard
  before insert on public.visa_documents
  for each row execute function private.guard_visa_document();

create or replace function private.notify_visa_document()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request uuid;
  v_customer uuid;
  v_label text := case when new.title <> '' then new.title
                       else private.visa_document_label(new.document_type) end;
begin
  select a.hiring_request_id, h.customer_id into v_request, v_customer
  from public.visa_applications a
  join public.hiring_requests h on h.id = a.hiring_request_id
  where a.id = new.application_id;
  perform private.notify_customer(v_customer, 'visa.document', 'New visa document',
    v_label || ' has been added to your visa application.', p_hiring => v_request);
  return null;
end;
$$;

revoke all on function private.notify_visa_document() from public, anon, authenticated;

create trigger visa_documents_notify
  after insert on public.visa_documents
  for each row execute function private.notify_visa_document();

-- -----------------------------------------------------------------------------
-- Access
-- -----------------------------------------------------------------------------
alter table public.visa_applications enable row level security;
alter table public.visa_application_steps enable row level security;
alter table public.visa_documents enable row level security;

revoke all on public.visa_applications from anon, authenticated;
revoke all on public.visa_application_steps from anon, authenticated;
revoke all on public.visa_documents from anon, authenticated;

grant select on public.visa_applications to authenticated;
grant update (route, visa_expires_on) on public.visa_applications to authenticated;
grant select on public.visa_application_steps to authenticated;
grant update (status, step_date, note) on public.visa_application_steps to authenticated;
grant select, delete on public.visa_documents to authenticated;
grant insert (application_id, document_type, title, storage_path, file_name, mime_type, size_bytes)
  on public.visa_documents to authenticated;

create policy "Customers and recruitment staff read visa applications"
  on public.visa_applications for select to authenticated
  using ((select private.is_recruitment_staff()) or private.owns_visa_application(id::text));

create policy "Recruitment staff update visa applications"
  on public.visa_applications for update to authenticated
  using ((select private.is_recruitment_staff()))
  with check ((select private.is_recruitment_staff()));

create policy "Customers and recruitment staff read visa steps"
  on public.visa_application_steps for select to authenticated
  using ((select private.is_recruitment_staff())
         or private.owns_visa_application(application_id::text));

create policy "Recruitment staff update visa steps"
  on public.visa_application_steps for update to authenticated
  using ((select private.is_recruitment_staff()))
  with check ((select private.is_recruitment_staff()));

create policy "Customers and recruitment staff read visa documents"
  on public.visa_documents for select to authenticated
  using ((select private.is_recruitment_staff())
         or private.owns_visa_application(application_id::text));

create policy "Recruitment staff add visa documents"
  on public.visa_documents for insert to authenticated
  with check ((select private.is_recruitment_staff()));

create policy "Recruitment staff remove visa documents"
  on public.visa_documents for delete to authenticated
  using ((select private.is_recruitment_staff()));

-- Files: a private bucket; staff upload and remove, the customer reads.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('visa-documents', 'visa-documents', false, 10485760,
        array['application/pdf', 'image/jpeg', 'image/png'])
on conflict (id) do nothing;

create policy "Recruitment staff upload visa files"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'visa-documents' and (select private.is_recruitment_staff()));

create policy "Customers and recruitment staff read visa files"
  on storage.objects for select to authenticated
  using (bucket_id = 'visa-documents'
         and ((select private.is_recruitment_staff())
              or private.owns_visa_application((storage.foldername(name))[1])));

create policy "Recruitment staff delete visa files"
  on storage.objects for delete to authenticated
  using (bucket_id = 'visa-documents' and (select private.is_recruitment_staff()));

-- -----------------------------------------------------------------------------
-- Expiry reminder: 7 days before (daily, 09:00 UAE)
-- -----------------------------------------------------------------------------
create or replace function private.send_visa_expiry_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  r record;
  v_count integer := 0;
  v_when text;
begin
  for r in
    select a.id, a.visa_expires_on, h.id as request_id, h.reference, h.customer_id
    from public.visa_applications a
    join public.hiring_requests h on h.id = a.hiring_request_id
    where a.visa_expires_on between v_today and v_today + 7
      and a.expiry_reminded_for is distinct from a.visa_expires_on
  loop
    v_when := to_char(r.visa_expires_on, 'FMDD Mon YYYY');
    perform private.notify_customer(r.customer_id, 'visa.expiring', 'Visa expires soon',
      'The visa for ' || r.reference || ' expires on ' || v_when
        || '. Contact Golden Maids to renew it.',
      p_hiring => r.request_id);
    perform private.notify_staff('recruitment', 'visa.expiring', 'Visa expires soon',
      r.reference || ': the visa expires on ' || v_when || '.',
      '/hiring-requests/view/?id=' || r.request_id::text);
    update public.visa_applications set expiry_reminded_for = r.visa_expires_on where id = r.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke all on function private.send_visa_expiry_reminders() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
    perform cron.schedule('visa-expiry-reminders', '0 5 * * *',
                          'select private.send_visa_expiry_reminders()');
  end if;
end;
$$;

-- Live updates for the app's visa page.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.visa_application_steps;
  end if;
end;
$$;
