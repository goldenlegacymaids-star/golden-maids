-- =============================================================================
-- Golden Maids – Service requests (employers) and billing documents
-- -----------------------------------------------------------------------------
-- * service_requests: what an employer asks the agency for in the app, other
--   than hiring a maid (hiring keeps its own hiring_requests):
--     maid_visa           2-Year Maid Visa (GCC sponsorship)
--     replacement         Free replacement
--     renewal             Visa or contract renewal
--     travel_noc          Maid travel NOC
--     travel_letter       Travel letter
--     salary_certificate  Salary certificate
--     problem             Report a problem
--     support             General support
--   Statuses: submitted → in_progress → ready → completed, or declined; the
--   customer can cancel while it is still "submitted". Reference SR-YYYY-NNNNNN.
--   A request can name one of the customer's own hiring requests (the maid),
--   or a maid by name (e.g. hired before the app). Travel requests carry the
--   country and dates.
-- * service_request_messages: replies between the customer and the agency.
-- * service_request_files: attachments from the customer (while the request
--   is open) and finished documents from staff (NOC, letter, certificate);
--   private bucket "service-request-files", folder = request id.
-- * customer_billing_documents: receipts and invoices administrators upload
--   as PDFs or images for a customer; private bucket "billing-documents",
--   folder = customer id. No money moves here.
-- * Customers only see their own; recruitment staff manage requests;
--   administrators manage billing documents. Customers and staff are notified.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Requests
-- -----------------------------------------------------------------------------
create sequence public.service_request_number_seq;

create table public.service_requests (
  id                   uuid primary key default gen_random_uuid(),
  reference            text not null unique,
  customer_id          uuid not null default auth.uid()
                         references public.profiles (id) on delete cascade,
  request_type         text not null check (request_type in (
                         'maid_visa', 'replacement', 'renewal', 'travel_noc',
                         'travel_letter', 'salary_certificate', 'problem', 'support')),
  -- The maid: one of the customer's hiring requests, or a name.
  hiring_request_id    uuid references public.hiring_requests (id) on delete set null,
  maid_name            text not null default '' check (char_length(maid_name) <= 120),
  -- Travel NOC and travel letter only.
  travel_country       text not null default '' check (char_length(travel_country) <= 80),
  travel_from          date,
  travel_to            date,
  details              text not null default '' check (char_length(details) <= 2000),
  status               text not null default 'submitted' check (status in (
                         'submitted', 'in_progress', 'ready', 'completed', 'declined',
                         'cancelled')),
  assigned_officer_id  uuid references public.profiles (id) on delete set null,
  closed_at            timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  check (travel_to is null or travel_from is null or travel_to >= travel_from)
);

comment on table public.service_requests is
  'Employer requests other than hiring (maid visa, replacement, renewal, travel NOC/letter, salary certificate, problems, support). Customers see their own; recruitment staff manage all.';

create index service_requests_customer_idx on public.service_requests (customer_id, created_at desc);
create index service_requests_status_idx on public.service_requests (status, created_at desc);
create index service_requests_type_idx on public.service_requests (request_type);
create index service_requests_hiring_idx on public.service_requests (hiring_request_id);
create index service_requests_officer_idx on public.service_requests (assigned_officer_id);

create trigger service_requests_set_updated_at
  before update on public.service_requests
  for each row execute function private.set_updated_at();

create or replace function private.service_request_label(p_type text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_type
    when 'maid_visa' then '2-Year Maid Visa'
    when 'replacement' then 'Free replacement'
    when 'renewal' then 'Visa or contract renewal'
    when 'travel_noc' then 'Maid travel NOC'
    when 'travel_letter' then 'Travel letter'
    when 'salary_certificate' then 'Salary certificate'
    when 'problem' then 'Report a problem'
    when 'support' then 'General support'
    else 'Request' end;
$$;

create or replace function private.service_request_status_label(p_status text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_status
    when 'submitted' then 'Sent'
    when 'in_progress' then 'In progress'
    when 'ready' then 'Ready'
    when 'completed' then 'Completed'
    when 'declined' then 'Declined'
    when 'cancelled' then 'Cancelled'
    else p_status end;
$$;

-- Whether the signed-in customer owns this request (as text, so storage
-- policies can pass a folder name).
create or replace function private.owns_service_request(p_request text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.service_requests
    where id::text = p_request and customer_id = (select auth.uid())
  );
$$;

-- Whether the request is still open (customers can add messages and files).
create or replace function private.service_request_is_open(p_request uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.service_requests
    where id = p_request and status in ('submitted', 'in_progress', 'ready')
  );
$$;

revoke all on function private.service_request_label(text) from public, anon, authenticated;
revoke all on function private.service_request_status_label(text) from public, anon, authenticated;
revoke all on function private.owns_service_request(text) from public, anon;
grant execute on function private.owns_service_request(text) to authenticated;
revoke all on function private.service_request_is_open(uuid) from public, anon, authenticated;

-- New request: the customer's own, a fresh reference, status "submitted";
-- the maid and travel details are checked.
create or replace function private.prepare_service_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_travel boolean := new.request_type in ('travel_noc', 'travel_letter');
  v_needs_maid boolean := new.request_type in
    ('replacement', 'renewal', 'travel_noc', 'travel_letter', 'salary_certificate');
begin
  if v_uid is null then
    raise exception 'Sign in to send a request.' using errcode = '42501';
  end if;
  new.customer_id := v_uid;
  new.maid_name := btrim(new.maid_name);
  new.travel_country := btrim(new.travel_country);
  new.details := btrim(new.details);

  if new.hiring_request_id is not null and not exists (
    select 1 from public.hiring_requests
    where id = new.hiring_request_id and customer_id = v_uid
  ) then
    raise exception 'Choose one of your own hiring requests.' using errcode = '42501';
  end if;
  if v_needs_maid and new.hiring_request_id is null and new.maid_name = '' then
    raise exception 'Choose the maid this request is for.' using errcode = '23514';
  end if;

  if v_travel then
    if new.travel_country = '' or new.travel_from is null then
      raise exception 'Enter the country and the date she leaves.' using errcode = '23514';
    end if;
  else
    new.travel_country := '';
    new.travel_from := null;
    new.travel_to := null;
  end if;

  if new.request_type in ('problem', 'support') and new.details = '' then
    raise exception 'Tell us what you need help with.' using errcode = '23514';
  end if;

  new.reference := 'SR-' || to_char(now(), 'YYYY') || '-'
                   || lpad(nextval('public.service_request_number_seq')::text, 6, '0');
  new.status := 'submitted';
  new.assigned_officer_id := null;
  new.closed_at := null;
  new.created_at := now();
  return new;
end;
$$;

revoke all on function private.prepare_service_request() from public, anon, authenticated;

create trigger service_requests_prepare
  before insert on public.service_requests
  for each row execute function private.prepare_service_request();

-- Updates: staff change status and officer; a customer can only cancel a
-- request that is still "submitted".
create or replace function private.guard_service_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (select private.is_recruitment_staff()) then
    if old.status <> 'submitted' or new.status <> 'cancelled'
       or new.assigned_officer_id is distinct from old.assigned_officer_id then
      raise exception 'Only a request that is still waiting can be cancelled.'
        using errcode = '42501';
    end if;
  elsif old.status in ('completed', 'declined', 'cancelled')
        and new.status is distinct from old.status then
    raise exception 'This request is closed.' using errcode = '23514';
  end if;

  if new.status in ('completed', 'declined', 'cancelled') then
    new.closed_at := coalesce(old.closed_at, now());
  end if;
  return new;
end;
$$;

revoke all on function private.guard_service_request() from public, anon, authenticated;

create trigger service_requests_guard
  before update on public.service_requests
  for each row execute function private.guard_service_request();

-- -----------------------------------------------------------------------------
-- Messages and files
-- -----------------------------------------------------------------------------
create table public.service_request_messages (
  id          bigint generated always as identity primary key,
  request_id  uuid not null references public.service_requests (id) on delete cascade,
  author_id   uuid default auth.uid() references public.profiles (id) on delete set null,
  from_staff  boolean not null default false,
  body        text not null check (char_length(body) between 1 and 1000),
  created_at  timestamptz not null default now()
);

comment on table public.service_request_messages is
  'Replies between the customer and the agency on a service request.';

create index service_request_messages_request_idx on public.service_request_messages (request_id, created_at);
create index service_request_messages_author_idx on public.service_request_messages (author_id);

create table public.service_request_files (
  id            uuid primary key default gen_random_uuid(),
  request_id    uuid not null references public.service_requests (id) on delete cascade,
  from_staff    boolean not null default false,
  title         text not null default '' check (char_length(title) <= 120),
  -- service-request-files/<request id>/<file>
  storage_path  text not null unique check (char_length(storage_path) <= 300),
  file_name     text not null check (char_length(file_name) between 1 and 200),
  mime_type     text not null check (mime_type in ('application/pdf', 'image/jpeg', 'image/png')),
  size_bytes    integer not null check (size_bytes between 1 and 10485760),
  uploaded_by   uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now()
);

comment on table public.service_request_files is
  'Attachments from the customer and finished documents from the agency for a service request; files in the private service-request-files bucket.';

create index service_request_files_request_idx on public.service_request_files (request_id, created_at);
create index service_request_files_uploaded_by_idx on public.service_request_files (uploaded_by);

create or replace function private.guard_service_request_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.author_id := (select auth.uid());
  new.from_staff := (select private.is_recruitment_staff());
  new.body := btrim(new.body);
  new.created_at := now();
  if not new.from_staff and not private.service_request_is_open(new.request_id) then
    raise exception 'This request is closed. Send a new request if you need anything else.'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_service_request_message() from public, anon, authenticated;

create trigger service_request_messages_guard
  before insert on public.service_request_messages
  for each row execute function private.guard_service_request_message();

create or replace function private.guard_service_request_file()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if split_part(new.storage_path, '/', 1) <> new.request_id::text then
    raise exception 'This file is not in the request''s folder.' using errcode = '42501';
  end if;
  new.from_staff := (select private.is_recruitment_staff());
  new.title := btrim(new.title);
  new.uploaded_by := (select auth.uid());
  new.created_at := now();
  if not new.from_staff then
    if not private.service_request_is_open(new.request_id) then
      raise exception 'This request is closed.' using errcode = '23514';
    end if;
    if (select count(*) from public.service_request_files
        where request_id = new.request_id and not from_staff) >= 10 then
      raise exception 'A request can have up to 10 attachments.' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.guard_service_request_file() from public, anon, authenticated;

create trigger service_request_files_guard
  before insert on public.service_request_files
  for each row execute function private.guard_service_request_file();

-- -----------------------------------------------------------------------------
-- Notifications
-- -----------------------------------------------------------------------------
alter table public.customer_notifications
  add column service_request_id uuid references public.service_requests (id) on delete cascade;

create index customer_notifications_service_request_idx
  on public.customer_notifications (service_request_id);

grant select (service_request_id) on public.customer_notifications to authenticated;

create or replace function private.notify_customer_service_request(
  p_request uuid, p_kind text, p_title text, p_body text
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.customer_notifications (customer_id, kind, title, body, service_request_id)
  select r.customer_id, p_kind, left(p_title, 160), left(coalesce(p_body, ''), 500), r.id
  from public.service_requests r
  where r.id = p_request;
$$;

revoke all on function private.notify_customer_service_request(uuid, text, text, text)
  from public, anon, authenticated;

-- New request → staff; status changed by staff → customer; cancelled by the
-- customer → staff.
create or replace function private.notify_service_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_label text := private.service_request_label(new.request_type);
  v_link text := '/requests/view/?id=' || new.id::text;
begin
  if tg_op = 'INSERT' then
    perform private.notify_staff('recruitment', 'request.new',
      case when new.request_type = 'problem' then 'Problem reported: ' || new.reference
           else 'New request: ' || v_label end,
      new.reference || ' · ' || v_label, v_link);
    return null;
  end if;

  if new.status = old.status then
    return null;
  end if;
  if new.status = 'cancelled' and not (select private.is_recruitment_staff()) then
    perform private.notify_staff('recruitment', 'request.cancelled',
      'Request cancelled: ' || new.reference,
      v_label || ' was cancelled by the customer.', v_link);
  else
    perform private.notify_customer_service_request(new.id, 'request.status',
      v_label || ' · ' || new.reference,
      'Status: ' || private.service_request_status_label(new.status) || '.');
  end if;
  return null;
end;
$$;

revoke all on function private.notify_service_request() from public, anon, authenticated;

create trigger service_requests_notify
  after insert or update of status on public.service_requests
  for each row execute function private.notify_service_request();

create or replace function private.notify_service_request_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.service_requests;
begin
  select * into r from public.service_requests where id = new.request_id;
  if new.from_staff then
    perform private.notify_customer_service_request(r.id, 'request.message',
      'Message about ' || r.reference, new.body);
  else
    perform private.notify_staff('recruitment', 'request.message',
      'Customer replied: ' || r.reference, new.body,
      '/requests/view/?id=' || r.id::text);
  end if;
  return null;
end;
$$;

revoke all on function private.notify_service_request_message() from public, anon, authenticated;

create trigger service_request_messages_notify
  after insert on public.service_request_messages
  for each row execute function private.notify_service_request_message();

create or replace function private.notify_service_request_file()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.service_requests;
begin
  if not new.from_staff then
    return null;
  end if;
  select * into r from public.service_requests where id = new.request_id;
  perform private.notify_customer_service_request(r.id, 'request.document',
    'New document for ' || r.reference,
    coalesce(nullif(new.title, ''), new.file_name) || ' is ready to open in the app.');
  return null;
end;
$$;

revoke all on function private.notify_service_request_file() from public, anon, authenticated;

create trigger service_request_files_notify
  after insert on public.service_request_files
  for each row execute function private.notify_service_request_file();

-- -----------------------------------------------------------------------------
-- Access: requests, messages, files
-- -----------------------------------------------------------------------------
alter table public.service_requests enable row level security;
alter table public.service_request_messages enable row level security;
alter table public.service_request_files enable row level security;

revoke all on public.service_requests from anon, authenticated;
revoke all on public.service_request_messages from anon, authenticated;
revoke all on public.service_request_files from anon, authenticated;
revoke all on sequence public.service_request_number_seq from anon, authenticated;

grant select on public.service_requests to authenticated;
grant insert (request_type, hiring_request_id, maid_name, travel_country, travel_from,
              travel_to, details)
  on public.service_requests to authenticated;
grant update (status, assigned_officer_id) on public.service_requests to authenticated;

grant select on public.service_request_messages to authenticated;
grant insert (request_id, body) on public.service_request_messages to authenticated;

grant select, delete on public.service_request_files to authenticated;
grant insert (request_id, title, storage_path, file_name, mime_type, size_bytes)
  on public.service_request_files to authenticated;

create policy "Customers and recruitment staff read service requests"
  on public.service_requests for select to authenticated
  using (customer_id = (select auth.uid()) or (select private.is_recruitment_staff()));

create policy "Customers send service requests"
  on public.service_requests for insert to authenticated
  with check (customer_id = (select auth.uid()));

create policy "Customers cancel and recruitment staff update service requests"
  on public.service_requests for update to authenticated
  using (customer_id = (select auth.uid()) or (select private.is_recruitment_staff()))
  with check (customer_id = (select auth.uid()) or (select private.is_recruitment_staff()));

create policy "Customers and recruitment staff read request messages"
  on public.service_request_messages for select to authenticated
  using ((select private.is_recruitment_staff())
         or private.owns_service_request(request_id::text));

create policy "Customers and recruitment staff write request messages"
  on public.service_request_messages for insert to authenticated
  with check ((select private.is_recruitment_staff())
              or private.owns_service_request(request_id::text));

create policy "Customers and recruitment staff read request files"
  on public.service_request_files for select to authenticated
  using ((select private.is_recruitment_staff())
         or private.owns_service_request(request_id::text));

create policy "Customers and recruitment staff add request files"
  on public.service_request_files for insert to authenticated
  with check ((select private.is_recruitment_staff())
              or private.owns_service_request(request_id::text));

-- Customers remove only their own attachments, while the request waits.
create policy "Staff remove request files; customers their own while waiting"
  on public.service_request_files for delete to authenticated
  using ((select private.is_recruitment_staff())
         or (not from_staff and uploaded_by = (select auth.uid())
             and exists (select 1 from public.service_requests r
                         where r.id = request_id and r.status = 'submitted'
                           and r.customer_id = (select auth.uid()))));

create trigger service_requests_audit
  after update or delete on public.service_requests
  for each row execute function private.log_admin_change();

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('service-request-files', 'service-request-files', false, 10485760,
        array['application/pdf', 'image/jpeg', 'image/png'])
on conflict (id) do nothing;

create policy "Customers and recruitment staff upload request files"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'service-request-files'
              and ((select private.is_recruitment_staff())
                   or private.owns_service_request((storage.foldername(name))[1])));

create policy "Customers and recruitment staff read request files in storage"
  on storage.objects for select to authenticated
  using (bucket_id = 'service-request-files'
         and ((select private.is_recruitment_staff())
              or private.owns_service_request((storage.foldername(name))[1])));

create policy "Staff delete request files; customers their own uploads"
  on storage.objects for delete to authenticated
  using (bucket_id = 'service-request-files'
         and ((select private.is_recruitment_staff())
              or (owner_id = (select auth.uid())::text
                  and private.owns_service_request((storage.foldername(name))[1]))));

-- -----------------------------------------------------------------------------
-- Billing documents (receipts and invoices)
-- -----------------------------------------------------------------------------
create table public.customer_billing_documents (
  id                 uuid primary key default gen_random_uuid(),
  -- Kept (without the customer) if the account is deleted, for the accounts.
  customer_id        uuid references public.profiles (id) on delete set null,
  kind               text not null check (kind in ('receipt', 'invoice')),
  number             text not null check (char_length(number) between 1 and 40),
  amount             numeric(10, 2) not null check (amount > 0 and amount <= 1000000),
  status             text check (status in ('unpaid', 'paid', 'cancelled')),
  issued_on          date not null,
  due_on             date,
  description        text not null default '' check (char_length(description) <= 200),
  hiring_request_id  uuid references public.hiring_requests (id) on delete set null,
  -- billing-documents/<customer id>/<file>
  storage_path       text not null unique check (char_length(storage_path) <= 300),
  file_name          text not null check (char_length(file_name) between 1 and 200),
  mime_type          text not null check (mime_type in ('application/pdf', 'image/jpeg', 'image/png')),
  size_bytes         integer not null check (size_bytes between 1 and 10485760),
  uploaded_by        uuid references public.profiles (id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (kind, number),
  -- Invoices have a status (and may have a due date); receipts have neither.
  check ((kind = 'invoice') = (status is not null)),
  check (kind = 'invoice' or due_on is null),
  check (due_on is null or due_on >= issued_on)
);

comment on table public.customer_billing_documents is
  'Receipts and invoices administrators upload for a customer; files in the private billing-documents bucket. No money moves here.';

create index customer_billing_documents_customer_idx
  on public.customer_billing_documents (customer_id, issued_on desc);
create index customer_billing_documents_hiring_idx
  on public.customer_billing_documents (hiring_request_id);
create index customer_billing_documents_uploaded_by_idx
  on public.customer_billing_documents (uploaded_by);

create trigger customer_billing_documents_set_updated_at
  before update on public.customer_billing_documents
  for each row execute function private.set_updated_at();

create or replace function private.guard_billing_document()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.customer_id is null
       or split_part(new.storage_path, '/', 1) <> new.customer_id::text then
      raise exception 'This file is not in the customer''s folder.' using errcode = '42501';
    end if;
    new.number := btrim(new.number);
    new.uploaded_by := (select auth.uid());
    new.created_at := now();
  elsif new.customer_id is distinct from old.customer_id or new.kind <> old.kind
        or new.storage_path <> old.storage_path then
    raise exception 'Upload a new document instead.' using errcode = '42501';
  end if;
  new.description := btrim(new.description);
  return new;
end;
$$;

revoke all on function private.guard_billing_document() from public, anon, authenticated;

create trigger customer_billing_documents_guard
  before insert or update on public.customer_billing_documents
  for each row execute function private.guard_billing_document();

create or replace function private.notify_billing_document()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.notify_customer(new.customer_id, 'billing.' || new.kind,
    case new.kind when 'receipt' then 'New receipt' else 'New invoice' end,
    new.number || ' · AED ' || to_char(new.amount, 'FM999,999,990.00')
      || ' is in your Wallet.');
  return null;
end;
$$;

revoke all on function private.notify_billing_document() from public, anon, authenticated;

create trigger customer_billing_documents_notify
  after insert on public.customer_billing_documents
  for each row execute function private.notify_billing_document();

create trigger customer_billing_documents_audit
  after insert or update or delete on public.customer_billing_documents
  for each row execute function private.log_admin_change();

alter table public.customer_billing_documents enable row level security;
revoke all on public.customer_billing_documents from anon, authenticated;

grant select, delete on public.customer_billing_documents to authenticated;
grant insert (customer_id, kind, number, amount, status, issued_on, due_on, description,
              hiring_request_id, storage_path, file_name, mime_type, size_bytes)
  on public.customer_billing_documents to authenticated;
grant update (status, due_on, description) on public.customer_billing_documents to authenticated;

create policy "Customers read their billing documents; admins read all"
  on public.customer_billing_documents for select to authenticated
  using (customer_id = (select auth.uid()) or (select private.is_admin()));

create policy "Admins add billing documents"
  on public.customer_billing_documents for insert to authenticated
  with check ((select private.is_admin()));

create policy "Admins update billing documents"
  on public.customer_billing_documents for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

create policy "Admins remove billing documents"
  on public.customer_billing_documents for delete to authenticated
  using ((select private.is_admin()));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('billing-documents', 'billing-documents', false, 10485760,
        array['application/pdf', 'image/jpeg', 'image/png'])
on conflict (id) do nothing;

create policy "Admins upload billing files"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'billing-documents' and (select private.is_admin()));

create policy "Customers and admins read billing files"
  on storage.objects for select to authenticated
  using (bucket_id = 'billing-documents'
         and ((select private.is_admin())
              or (storage.foldername(name))[1] = (select auth.uid())::text));

create policy "Admins delete billing files"
  on storage.objects for delete to authenticated
  using (bucket_id = 'billing-documents' and (select private.is_admin()));

-- Live updates for the app's request page.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.service_requests;
    alter publication supabase_realtime add table public.service_request_messages;
  end if;
end;
$$;
