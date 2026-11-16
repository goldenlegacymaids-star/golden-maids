-- =============================================================================
-- Golden Maids – Recruitment routes (maid in / outside the UAE) and
-- customer documents (My Documents)
-- =============================================================================
-- 1. Each maid is either in the UAE or outside it (existing maids: in the UAE).
-- 2. Each nationality can have an arrival time from abroad, in days (From–To).
-- 3. Hiring requests keep where the maid is (the chosen maid's, or the
--    customer's choice when the agency recommends).
-- 4. Customers upload their documents for the GCC Sponsor visa (Emirates ID,
--    passport copy, salary certificate, marriage certificate) into a PRIVATE
--    storage bucket. Only the customer and recruitment staff/admins can open
--    them. Staff approve a document or ask for a new copy (with a reason);
--    the customer gets an in-app notification. New uploads notify staff.
--    An account can only be deleted after its documents are removed (the
--    staff website does this first), so no files are left behind.

-- -----------------------------------------------------------------------------
-- 1. Maid location
-- -----------------------------------------------------------------------------
alter table public.candidates
  add column location text not null default 'in_uae'
    check (location in ('in_uae', 'outside_uae'));

comment on column public.candidates.location is
  'Where the maid is now: in_uae or outside_uae (outside = arrival time from her nationality).';

create index candidates_location_idx on public.candidates (location);

grant select (location) on public.candidates to anon;

-- -----------------------------------------------------------------------------
-- 2. Arrival time from abroad, per nationality (days)
-- -----------------------------------------------------------------------------
alter table public.maid_nationalities
  add column arrival_days_min integer check (arrival_days_min between 1 and 365),
  add column arrival_days_max integer check (arrival_days_max between 1 and 365),
  add constraint maid_nationalities_arrival_check check (
    (arrival_days_min is null and arrival_days_max is null)
    or (arrival_days_min is not null and arrival_days_max is not null
        and arrival_days_min <= arrival_days_max)
  );

comment on column public.maid_nationalities.arrival_days_min is
  'Shortest time, in days, for a maid of this nationality to arrive from abroad (null = on request).';

-- -----------------------------------------------------------------------------
-- 3. Where the maid is, on hiring requests
-- -----------------------------------------------------------------------------
alter table public.hiring_requests
  add column maid_location text check (maid_location is null or maid_location in ('in_uae', 'outside_uae'));

comment on column public.hiring_requests.maid_location is
  'The chosen maid''s location, or the customer''s choice when the agency recommends.';

grant insert (maid_location) on public.hiring_requests to authenticated;

create or replace function private.prepare_hiring_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_package public.recruitment_packages%rowtype;
  v_candidate_nationality text;
  v_candidate_location text;
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
    select c.nationality, c.location into v_candidate_nationality, v_candidate_location
    from public.candidates c
    where c.id = new.candidate_id and c.is_published and c.archived_at is null
      and c.availability_status = 'available';
    if not found then
      raise exception 'This worker is no longer available.' using errcode = '23514';
    end if;
    -- The chosen maid decides the nationality and the location.
    new.preferred_nationality := v_candidate_nationality;
    new.maid_location := v_candidate_location;
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

-- -----------------------------------------------------------------------------
-- 4. Customer documents
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('customer-documents', 'customer-documents', false, 10485760,
        array['application/pdf', 'image/jpeg', 'image/png'])
on conflict (id) do nothing;

create table public.customer_documents (
  id             uuid primary key default gen_random_uuid(),
  customer_id    uuid not null references public.profiles (id) on delete cascade,
  document_type  text not null check (document_type in
                   ('emirates_id', 'passport', 'salary_certificate', 'marriage_certificate')),
  -- customer-documents/<customer id>/<file>
  storage_path   text not null unique check (char_length(storage_path) <= 300),
  file_name      text not null check (char_length(file_name) between 1 and 200),
  mime_type      text not null check (mime_type in ('application/pdf', 'image/jpeg', 'image/png')),
  size_bytes     integer not null check (size_bytes between 1 and 10485760),
  status         text not null default 'submitted'
                   check (status in ('submitted', 'approved', 'needs_new_copy')),
  staff_note     text not null default '' check (char_length(staff_note) <= 500),
  reviewed_by    uuid references public.profiles (id) on delete set null,
  reviewed_at    timestamptz,
  uploaded_at    timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  -- One current file per document type; a new upload replaces it.
  unique (customer_id, document_type)
);

comment on table public.customer_documents is
  'Documents customers upload for the GCC Sponsor visa; files in the private customer-documents bucket.';

create index customer_documents_status_idx on public.customer_documents (status, updated_at desc);
create index customer_documents_reviewed_by_idx on public.customer_documents (reviewed_by);

create trigger customer_documents_set_updated_at
  before update on public.customer_documents
  for each row execute function private.set_updated_at();

-- Who may change what: the customer uploads and replaces files (which sends the
-- document back for review); recruitment staff only set the review.
create or replace function private.guard_customer_document()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_file_changed boolean;
begin
  if tg_op = 'INSERT' then
    new.customer_id := v_uid;
    if v_uid is null then
      raise exception 'Please sign in to upload documents.' using errcode = '42501';
    end if;
    if split_part(new.storage_path, '/', 1) <> v_uid::text then
      raise exception 'This file is not in your folder.' using errcode = '42501';
    end if;
    new.status := 'submitted';
    new.staff_note := '';
    new.reviewed_by := null;
    new.reviewed_at := null;
    new.uploaded_at := now();
    return new;
  end if;

  if new.customer_id <> old.customer_id or new.document_type <> old.document_type then
    raise exception 'The owner and type of a document cannot change.' using errcode = '42501';
  end if;

  v_file_changed := new.storage_path <> old.storage_path
    or new.file_name <> old.file_name
    or new.mime_type <> old.mime_type
    or new.size_bytes <> old.size_bytes;

  if v_file_changed then
    if v_uid is distinct from old.customer_id then
      raise exception 'Only the customer can replace this document.' using errcode = '42501';
    end if;
    if split_part(new.storage_path, '/', 1) <> v_uid::text then
      raise exception 'This file is not in your folder.' using errcode = '42501';
    end if;
    -- A new copy goes back to the agency for review.
    new.status := 'submitted';
    new.staff_note := '';
    new.reviewed_by := null;
    new.reviewed_at := null;
    new.uploaded_at := now();
    return new;
  end if;

  if new.status <> old.status or new.staff_note <> old.staff_note then
    if not (select private.is_recruitment_staff()) then
      raise exception 'Only the agency can review documents.' using errcode = '42501';
    end if;
    new.staff_note := btrim(new.staff_note);
    if new.status = 'needs_new_copy' and new.staff_note = '' then
      raise exception 'Please tell the customer why a new copy is needed.' using errcode = '23514';
    end if;
    if new.status = 'submitted' then
      raise exception 'Choose Approved or Needs a new copy.' using errcode = '23514';
    end if;
    new.reviewed_by := v_uid;
    new.reviewed_at := now();
  end if;
  return new;
end;
$$;

revoke all on function private.guard_customer_document() from public, anon, authenticated;

create trigger customer_documents_guard
  before insert or update on public.customer_documents
  for each row execute function private.guard_customer_document();

alter table public.customer_documents enable row level security;

revoke all on public.customer_documents from anon, authenticated;
grant select, delete on public.customer_documents to authenticated;
grant insert (document_type, storage_path, file_name, mime_type, size_bytes)
  on public.customer_documents to authenticated;
grant update (storage_path, file_name, mime_type, size_bytes, status, staff_note)
  on public.customer_documents to authenticated;

create policy "Customers and recruitment staff read documents"
  on public.customer_documents for select to authenticated
  using (customer_id = (select auth.uid()) or (select private.is_recruitment_staff()));

create policy "Customers add their documents"
  on public.customer_documents for insert to authenticated
  with check (customer_id = (select auth.uid()));

create policy "Customers and recruitment staff update documents"
  on public.customer_documents for update to authenticated
  using (customer_id = (select auth.uid()) or (select private.is_recruitment_staff()))
  with check (customer_id = (select auth.uid()) or (select private.is_recruitment_staff()));

create policy "Customers and recruitment staff delete documents"
  on public.customer_documents for delete to authenticated
  using (customer_id = (select auth.uid()) or (select private.is_recruitment_staff()));

-- Files: customers only inside their own folder; staff read and delete.
create policy "Customers upload their document files"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'customer-documents'
              and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "Customers and recruitment staff read document files"
  on storage.objects for select to authenticated
  using (bucket_id = 'customer-documents'
         and ((storage.foldername(name))[1] = (select auth.uid())::text
              or (select private.is_recruitment_staff())));

create policy "Customers and recruitment staff delete document files"
  on storage.objects for delete to authenticated
  using (bucket_id = 'customer-documents'
         and ((storage.foldername(name))[1] = (select auth.uid())::text
              or (select private.is_recruitment_staff())));

-- Notifications: staff hear about new uploads; customers about the review.
create or replace function private.notify_customer_document()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_label text := case new.document_type
    when 'emirates_id' then 'Emirates ID'
    when 'passport' then 'Passport copy'
    when 'salary_certificate' then 'Salary certificate'
    else 'Marriage certificate' end;
  v_customer text;
begin
  if new.status = 'submitted'
     and (tg_op = 'INSERT' or new.storage_path <> old.storage_path) then
    select coalesce(nullif(btrim(p.full_name), ''), 'A customer') into v_customer
    from public.profiles p where p.id = new.customer_id;
    perform private.notify_staff('recruitment', 'document.uploaded',
      'New document to review',
      coalesce(v_customer, 'A customer') || ' uploaded: ' || v_label || '.',
      '/documents/');
  elsif tg_op = 'UPDATE' and new.status <> old.status then
    if new.status = 'approved' then
      perform private.notify_customer(new.customer_id, 'document.approved',
        'Document approved', 'Your ' || v_label || ' has been approved.');
    elsif new.status = 'needs_new_copy' then
      perform private.notify_customer(new.customer_id, 'document.needs_new_copy',
        'Please upload a new copy',
        'Your ' || v_label || ' needs a new copy: ' || new.staff_note);
    end if;
  end if;
  return null;
end;
$$;

revoke all on function private.notify_customer_document() from public, anon, authenticated;

create trigger customer_documents_notify
  after insert or update on public.customer_documents
  for each row execute function private.notify_customer_document();

-- Account deletion: documents (and their files) must be removed first.
create or replace function private.guard_deletion_documents()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'completed' and old.status <> 'completed'
     and exists (select 1 from public.customer_documents d where d.customer_id = new.user_id) then
    raise exception 'Remove the customer''s documents first.' using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_deletion_documents() from public, anon, authenticated;

create trigger account_deletion_requests_documents_guard
  before update of status on public.account_deletion_requests
  for each row execute function private.guard_deletion_documents();
