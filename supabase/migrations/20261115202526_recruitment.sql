-- =============================================================================
-- Golden Maids – Recruitment: packages, candidates, favourites, hiring requests
--
-- Privacy model
--   * public.candidates holds only what customers may see. Guests (anon) can
--     read the card columns only; signed-in users can read the full profile
--     columns (column-level grants, enforced by the database).
--   * private details (full name, date of birth, passport number) live in
--     public.candidate_private_details, readable by recruitment staff only.
--     The public age is kept up to date by a trigger and a daily job.
--   * Candidate documents are in a private bucket; customers can open only
--     documents marked customer-visible, and passports can never be marked so.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Helper: recruitment staff (admins and recruitment officers).
-- -----------------------------------------------------------------------------
create or replace function private.is_recruitment_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_any_role(array['super_admin', 'admin', 'recruitment_officer']);
$$;

revoke all on function private.is_recruitment_staff() from public, anon;
grant execute on function private.is_recruitment_staff() to authenticated;

-- -----------------------------------------------------------------------------
-- recruitment_packages
-- -----------------------------------------------------------------------------
create table public.recruitment_packages (
  id                          uuid primary key default gen_random_uuid(),
  slug                        text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name                        text not null check (char_length(name) between 1 and 80),
  description                 text not null default '' check (char_length(description) <= 1000),
  -- 'company' = maid on the company's visa; 'sponsor' = customer sponsors the visa.
  visa_type                   text not null check (visa_type in ('company', 'sponsor')),
  contract_term               text not null check (contract_term in ('monthly', 'yearly', 'two_year')),
  -- Durations the customer may choose (in months).
  min_months                  integer not null check (min_months > 0),
  max_months                  integer not null,
  month_step                  integer not null default 1 check (month_step > 0),
  -- GCC sponsor packages need the sponsor's nationality.
  requires_sponsor_nationality boolean not null default false,
  -- Set by administrators; null = "Price on request".
  price                       numeric(10, 2) check (price is null or price >= 0),
  price_unit                  text check (price_unit in ('per_month', 'total')),
  sort_order                  integer not null default 0,
  is_active                   boolean not null default true,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  constraint recruitment_packages_months check (max_months >= min_months),
  constraint recruitment_packages_price_unit check (price is null or price_unit is not null)
);

comment on table public.recruitment_packages is
  'Hiring packages (monthly/yearly company visa, 2-year GCC sponsor). Admin-managed.';

create trigger recruitment_packages_set_updated_at
  before update on public.recruitment_packages
  for each row execute function private.set_updated_at();
create trigger recruitment_packages_audit
  after insert or update or delete on public.recruitment_packages
  for each row execute function private.log_admin_change();

-- -----------------------------------------------------------------------------
-- candidates (customer-visible data only)
-- -----------------------------------------------------------------------------
create sequence public.candidate_code_seq;

create table public.candidates (
  id                  uuid primary key default gen_random_uuid(),
  code                text not null unique
                      default ('GM-' || lpad(nextval('public.candidate_code_seq')::text, 5, '0')),
  -- Shown instead of the code only when the admin allows the name to be shown.
  display_name        text check (display_name is null or char_length(display_name) <= 120),
  show_full_name      boolean not null default false,
  -- Path in the public 'candidate-photos' bucket.
  photo_path          text check (photo_path is null or char_length(photo_path) <= 300),
  -- Path in the private 'candidate-documents' bucket (admin-uploaded video).
  video_path          text check (video_path is null or char_length(video_path) <= 300),
  nationality         text not null check (nationality in
                        ('Kenya', 'Ethiopia', 'Myanmar', 'Philippines', 'Indonesia')),
  -- Maintained from the private date of birth (trigger + daily job).
  age                 integer check (age is null or age between 18 and 80),
  designation         text not null default 'Housemaid' check (char_length(designation) between 1 and 60),
  accommodation       text not null default 'live_in' check (accommodation in ('live_in', 'live_out')),
  years_experience    integer not null default 0 check (years_experience between 0 and 50),
  highest_qualification text check (highest_qualification is null or char_length(highest_qualification) <= 120),
  religion            text check (religion is null or religion in
                        ('Christian', 'Muslim', 'Buddhist', 'Hindu', 'Other')),
  marital_status      text check (marital_status is null or marital_status in
                        ('Single', 'Married', 'Divorced', 'Widowed')),
  -- Monthly salary expectation in AED (admin-entered).
  expected_salary     numeric(10, 2) check (expected_salary is null or expected_salary >= 0),
  availability_status text not null default 'available'
                      check (availability_status in ('available', 'reserved', 'hired', 'unavailable')),
  available_from      date,
  bio                 text not null default '' check (char_length(bio) <= 2000),
  is_published        boolean not null default false,
  is_featured         boolean not null default false,
  -- Test records (to be deleted before launch).
  is_test             boolean not null default false,
  -- Date the candidate agreed to be listed (UAE PDPL). Required to publish.
  consent_obtained_at timestamptz,
  archived_at         timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint candidates_publish_requires_consent
    check (not is_published or consent_obtained_at is not null),
  constraint candidates_name_only_when_allowed
    check (show_full_name or display_name is null)
);

comment on table public.candidates is
  'Domestic-worker candidates as shown to customers. Private details are in candidate_private_details.';

create index candidates_listing_idx
  on public.candidates (is_published, availability_status, created_at desc);
create index candidates_nationality_idx on public.candidates (nationality);
create index candidates_featured_idx on public.candidates (is_featured) where is_featured;

create trigger candidates_set_updated_at
  before update on public.candidates
  for each row execute function private.set_updated_at();
create trigger candidates_audit
  after insert or update or delete on public.candidates
  for each row execute function private.log_admin_change();

-- Live = published, not archived. Used by policies below.
create or replace function private.is_live_candidate(p_candidate_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.candidates c
    where c.id = p_candidate_id and c.is_published and c.archived_at is null
  );
$$;

revoke all on function private.is_live_candidate(uuid) from public;
grant execute on function private.is_live_candidate(uuid) to anon, authenticated;
grant usage on schema private to anon;

-- -----------------------------------------------------------------------------
-- candidate_private_details (recruitment staff only)
-- -----------------------------------------------------------------------------
create table public.candidate_private_details (
  candidate_id     uuid primary key references public.candidates (id) on delete cascade,
  full_name        text not null check (char_length(full_name) between 1 and 120),
  date_of_birth    date not null check (date_of_birth > date '1940-01-01'),
  passport_number  text check (passport_number is null or char_length(passport_number) <= 30),
  internal_notes   text not null default '' check (char_length(internal_notes) <= 4000),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

comment on table public.candidate_private_details is
  'Personal details of candidates. Recruitment staff only; never shown to customers.';

create trigger candidate_private_details_set_updated_at
  before update on public.candidate_private_details
  for each row execute function private.set_updated_at();
create trigger candidate_private_details_audit
  after insert or update or delete on public.candidate_private_details
  for each row execute function private.log_admin_change();

-- Keep candidates.age and candidates.display_name in sync with private data.
create or replace function private.sync_candidate_public_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.candidates c
  set age = date_part('year', age(current_date, new.date_of_birth))::integer,
      display_name = case when c.show_full_name then new.full_name else null end
  where c.id = new.candidate_id;
  return new;
end;
$$;

revoke all on function private.sync_candidate_public_fields() from public, anon, authenticated;

create trigger candidate_private_details_sync
  after insert or update of full_name, date_of_birth on public.candidate_private_details
  for each row execute function private.sync_candidate_public_fields();

-- When the "show full name" switch changes, refresh display_name.
create or replace function private.apply_candidate_name_visibility()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.show_full_name then
    select d.full_name into new.display_name
    from public.candidate_private_details d
    where d.candidate_id = new.id;
  else
    new.display_name := null;
  end if;
  return new;
end;
$$;

revoke all on function private.apply_candidate_name_visibility() from public, anon, authenticated;

create trigger candidates_name_visibility
  before insert or update of show_full_name on public.candidates
  for each row execute function private.apply_candidate_name_visibility();

-- Daily refresh of ages (birthdays).
create or replace function private.refresh_candidate_ages()
returns void
language sql
security definer
set search_path = ''
as $$
  update public.candidates c
  set age = date_part('year', age(current_date, d.date_of_birth))::integer
  from public.candidate_private_details d
  where d.candidate_id = c.id
    and c.age is distinct from date_part('year', age(current_date, d.date_of_birth))::integer;
$$;

revoke all on function private.refresh_candidate_ages() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Profile detail tables (signed-in users only)
-- -----------------------------------------------------------------------------
create table public.candidate_skills (
  candidate_id  uuid not null references public.candidates (id) on delete cascade,
  skill         text not null check (skill in (
                  'cleaning', 'cooking', 'childcare', 'elderly_care', 'laundry',
                  'ironing', 'pet_care', 'household_management', 'driving')),
  primary key (candidate_id, skill)
);

create table public.candidate_languages (
  candidate_id  uuid not null references public.candidates (id) on delete cascade,
  language      text not null check (char_length(language) between 1 and 40),
  proficiency   text not null default 'good' check (proficiency in ('basic', 'good', 'fluent')),
  primary key (candidate_id, language)
);

create table public.candidate_experience (
  id            uuid primary key default gen_random_uuid(),
  candidate_id  uuid not null references public.candidates (id) on delete cascade,
  country       text not null check (char_length(country) between 1 and 60),
  role          text not null check (char_length(role) between 1 and 80),
  start_year    integer not null check (start_year between 1980 and 2100),
  end_year      integer check (end_year is null or end_year between 1980 and 2100),
  description   text not null default '' check (char_length(description) <= 1000),
  constraint candidate_experience_years check (end_year is null or end_year >= start_year)
);
create index candidate_experience_candidate_idx on public.candidate_experience (candidate_id);

create table public.candidate_packages (
  candidate_id  uuid not null references public.candidates (id) on delete cascade,
  package_id    uuid not null references public.recruitment_packages (id) on delete cascade,
  primary key (candidate_id, package_id)
);
create index candidate_packages_package_idx on public.candidate_packages (package_id);

create table public.candidate_documents (
  id                   uuid primary key default gen_random_uuid(),
  candidate_id         uuid not null references public.candidates (id) on delete cascade,
  document_type        text not null check (document_type in (
                         'passport', 'visa', 'medical', 'police_clearance',
                         'certificate', 'experience_letter', 'training', 'other')),
  title                text not null check (char_length(title) between 1 and 120),
  -- Path in the private 'candidate-documents' bucket.
  storage_path         text not null unique check (char_length(storage_path) <= 300),
  is_customer_visible  boolean not null default false,
  created_at           timestamptz not null default now(),
  -- Identity and medical documents can never be shown to customers.
  constraint candidate_documents_sensitive_never_visible check (
    not is_customer_visible
    or document_type in ('certificate', 'experience_letter', 'training', 'other')
  )
);
create index candidate_documents_candidate_idx on public.candidate_documents (candidate_id);

create trigger candidate_documents_audit
  after insert or update or delete on public.candidate_documents
  for each row execute function private.log_admin_change();

-- -----------------------------------------------------------------------------
-- Favourites
-- -----------------------------------------------------------------------------
create table public.candidate_favourites (
  user_id       uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  candidate_id  uuid not null references public.candidates (id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (user_id, candidate_id)
);
create index candidate_favourites_candidate_idx on public.candidate_favourites (candidate_id);

-- -----------------------------------------------------------------------------
-- Hiring requests
-- -----------------------------------------------------------------------------
create sequence public.hiring_request_number_seq;

create table public.hiring_requests (
  id                   uuid primary key default gen_random_uuid(),
  reference            text not null unique,
  customer_id          uuid not null default auth.uid() references public.profiles (id) on delete restrict,
  package_id           uuid not null references public.recruitment_packages (id) on delete restrict,
  duration_months      integer not null check (duration_months > 0),
  -- GCC sponsor packages: the sponsor's nationality (ISO country code).
  sponsor_nationality  text check (sponsor_nationality is null or sponsor_nationality in
                         ('AE', 'SA', 'QA', 'KW', 'BH', 'OM')),
  -- Null = the agency recommends a worker.
  candidate_id         uuid references public.candidates (id) on delete set null,
  -- Snapshot of the customer's details at submission.
  customer_name        text not null check (char_length(customer_name) between 2 and 120),
  customer_phone       text not null check (char_length(customer_phone) between 6 and 20),
  customer_email       text check (customer_email is null or char_length(customer_email) <= 254),
  emirate              text not null check (emirate in ('Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman',
                         'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah')),
  -- Household and requirements.
  household_size       integer check (household_size is null or household_size between 1 and 30),
  has_children         boolean not null default false,
  has_elderly          boolean not null default false,
  has_pets             boolean not null default false,
  preferred_start_date date,
  requirements         text not null default '' check (char_length(requirements) <= 2000),
  contact_method       text not null default 'phone' check (contact_method in ('phone', 'whatsapp', 'email')),
  status               text not null default 'submitted' check (status in (
                         'submitted', 'under_review', 'shortlisted', 'interview_scheduled',
                         'offer_accepted', 'visa_processing', 'completed', 'cancelled', 'rejected')),
  assigned_officer_id  uuid references public.profiles (id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

comment on table public.hiring_requests is
  'Customer requests to hire a domestic worker. Customers see their own; recruitment staff manage all.';

create index hiring_requests_customer_idx on public.hiring_requests (customer_id, created_at desc);
create index hiring_requests_status_idx on public.hiring_requests (status, created_at desc);
create index hiring_requests_candidate_idx on public.hiring_requests (candidate_id);
create index hiring_requests_package_idx on public.hiring_requests (package_id);
create index hiring_requests_officer_idx on public.hiring_requests (assigned_officer_id);

create trigger hiring_requests_set_updated_at
  before update on public.hiring_requests
  for each row execute function private.set_updated_at();

-- Reference number and validation on submission.
create or replace function private.prepare_hiring_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_package public.recruitment_packages%rowtype;
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

  if new.candidate_id is not null and not exists (
    select 1 from public.candidates c
    where c.id = new.candidate_id and c.is_published and c.archived_at is null
      and c.availability_status = 'available'
  ) then
    raise exception 'This worker is no longer available.' using errcode = '23514';
  end if;

  new.reference := 'HR-' || to_char(now(), 'YYYY') || '-'
                   || lpad(nextval('public.hiring_request_number_seq')::text, 6, '0');
  new.status := 'submitted';
  new.assigned_officer_id := null;
  return new;
end;
$$;

revoke all on function private.prepare_hiring_request() from public, anon, authenticated;

create trigger hiring_requests_prepare
  before insert on public.hiring_requests
  for each row execute function private.prepare_hiring_request();

-- Customers may only cancel; staff may change status and the assigned officer.
create or replace function private.guard_hiring_request_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select private.is_recruitment_staff()) then
    return new;
  end if;
  if new.status <> 'cancelled'
     or old.status not in ('submitted', 'under_review')
     or new.assigned_officer_id is distinct from old.assigned_officer_id then
    raise exception 'You can only cancel a request that has not been processed yet.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_hiring_request_update() from public, anon, authenticated;

create trigger hiring_requests_guard_update
  before update on public.hiring_requests
  for each row execute function private.guard_hiring_request_update();

-- -----------------------------------------------------------------------------
-- Hiring request history (status timeline)
-- -----------------------------------------------------------------------------
create table public.hiring_request_history (
  id                   bigint generated always as identity primary key,
  request_id           uuid not null references public.hiring_requests (id) on delete cascade,
  status               text not null,
  note                 text not null default '' check (char_length(note) <= 2000),
  is_customer_visible  boolean not null default true,
  created_by           uuid default auth.uid() references public.profiles (id) on delete set null,
  created_at           timestamptz not null default now()
);
create index hiring_request_history_request_idx on public.hiring_request_history (request_id, created_at);
create index hiring_request_history_created_by_idx on public.hiring_request_history (created_by);

create or replace function private.record_hiring_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.hiring_request_history (request_id, status, created_by)
    values (new.id, new.status, (select auth.uid()));
  end if;
  return new;
end;
$$;

revoke all on function private.record_hiring_status() from public, anon, authenticated;

create trigger hiring_requests_history
  after insert or update of status on public.hiring_requests
  for each row execute function private.record_hiring_status();

-- -----------------------------------------------------------------------------
-- Row Level Security and privileges
-- -----------------------------------------------------------------------------
alter table public.recruitment_packages      enable row level security;
alter table public.candidates                enable row level security;
alter table public.candidate_private_details enable row level security;
alter table public.candidate_skills          enable row level security;
alter table public.candidate_languages       enable row level security;
alter table public.candidate_experience      enable row level security;
alter table public.candidate_packages        enable row level security;
alter table public.candidate_documents       enable row level security;
alter table public.candidate_favourites      enable row level security;
alter table public.hiring_requests           enable row level security;
alter table public.hiring_request_history    enable row level security;

revoke all on public.recruitment_packages, public.candidates, public.candidate_private_details,
  public.candidate_skills, public.candidate_languages, public.candidate_experience,
  public.candidate_packages, public.candidate_documents, public.candidate_favourites,
  public.hiring_requests, public.hiring_request_history
  from anon, authenticated;

grant usage on sequence public.candidate_code_seq to authenticated;

-- Packages: everyone reads active ones; admins manage.
grant select on public.recruitment_packages to anon, authenticated;
grant insert, update, delete on public.recruitment_packages to authenticated;
create policy "Guests read active packages" on public.recruitment_packages
  for select to anon using (is_active);
create policy "Users read active packages; admins read all" on public.recruitment_packages
  for select to authenticated using (is_active or (select private.is_admin()));
create policy "Admins add packages" on public.recruitment_packages
  for insert to authenticated with check ((select private.is_admin()));
create policy "Admins update packages" on public.recruitment_packages
  for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));
create policy "Admins delete packages" on public.recruitment_packages
  for delete to authenticated using ((select private.is_admin()));

-- Candidates: guests read card columns of live candidates; signed-in users
-- read all public columns of live candidates; recruitment staff manage all.
grant select (id, code, display_name, photo_path, nationality, age, designation,
              accommodation, years_experience, expected_salary, availability_status,
              available_from, is_featured, is_test, created_at)
  on public.candidates to anon;
grant select on public.candidates to authenticated;
grant insert, update, delete on public.candidates to authenticated;

create policy "Guests read live candidates" on public.candidates
  for select to anon using (is_published and archived_at is null);
create policy "Users read live candidates; staff read all" on public.candidates
  for select to authenticated
  using ((is_published and archived_at is null) or (select private.is_recruitment_staff()));
create policy "Staff add candidates" on public.candidates
  for insert to authenticated with check ((select private.is_recruitment_staff()));
create policy "Staff update candidates" on public.candidates
  for update to authenticated
  using ((select private.is_recruitment_staff()))
  with check ((select private.is_recruitment_staff()));
create policy "Admins delete candidates" on public.candidates
  for delete to authenticated using ((select private.is_admin()));

-- Private details: recruitment staff only.
grant select, insert, update, delete on public.candidate_private_details to authenticated;
create policy "Staff manage private details" on public.candidate_private_details
  for all to authenticated
  using ((select private.is_recruitment_staff()))
  with check ((select private.is_recruitment_staff()));

-- Skills, languages, experience, packages: signed-in users read live
-- candidates' rows; staff manage. Work history is signed-in only.
grant select on public.candidate_skills, public.candidate_languages,
  public.candidate_experience, public.candidate_packages to authenticated;
grant insert, update, delete on public.candidate_skills, public.candidate_languages,
  public.candidate_experience, public.candidate_packages to authenticated;
-- Skills, languages and packages are not sensitive: guests can filter by them.
grant select on public.candidate_skills, public.candidate_languages,
  public.candidate_packages to anon;

create policy "Guests read skills of live candidates" on public.candidate_skills
  for select to anon using ((select private.is_live_candidate(candidate_id)));
create policy "Users read skills of live candidates" on public.candidate_skills
  for select to authenticated
  using ((select private.is_live_candidate(candidate_id)) or (select private.is_recruitment_staff()));
create policy "Staff manage skills" on public.candidate_skills
  for all to authenticated
  using ((select private.is_recruitment_staff())) with check ((select private.is_recruitment_staff()));

create policy "Guests read languages of live candidates" on public.candidate_languages
  for select to anon using ((select private.is_live_candidate(candidate_id)));
create policy "Users read languages of live candidates" on public.candidate_languages
  for select to authenticated
  using ((select private.is_live_candidate(candidate_id)) or (select private.is_recruitment_staff()));
create policy "Staff manage languages" on public.candidate_languages
  for all to authenticated
  using ((select private.is_recruitment_staff())) with check ((select private.is_recruitment_staff()));

create policy "Users read experience of live candidates" on public.candidate_experience
  for select to authenticated
  using ((select private.is_live_candidate(candidate_id)) or (select private.is_recruitment_staff()));
create policy "Staff manage experience" on public.candidate_experience
  for all to authenticated
  using ((select private.is_recruitment_staff())) with check ((select private.is_recruitment_staff()));

create policy "Guests read packages of live candidates" on public.candidate_packages
  for select to anon using ((select private.is_live_candidate(candidate_id)));
create policy "Users read packages of live candidates" on public.candidate_packages
  for select to authenticated
  using ((select private.is_live_candidate(candidate_id)) or (select private.is_recruitment_staff()));
create policy "Staff manage candidate packages" on public.candidate_packages
  for all to authenticated
  using ((select private.is_recruitment_staff())) with check ((select private.is_recruitment_staff()));

-- Documents: signed-in users see customer-visible documents of live
-- candidates; staff manage all.
grant select, insert, update, delete on public.candidate_documents to authenticated;
create policy "Users read visible documents of live candidates" on public.candidate_documents
  for select to authenticated
  using (
    (is_customer_visible and (select private.is_live_candidate(candidate_id)))
    or (select private.is_recruitment_staff())
  );
create policy "Staff manage documents" on public.candidate_documents
  for all to authenticated
  using ((select private.is_recruitment_staff())) with check ((select private.is_recruitment_staff()));

-- Favourites: each user manages their own.
grant select, insert, delete on public.candidate_favourites to authenticated;
create policy "Users read own favourites" on public.candidate_favourites
  for select to authenticated using (user_id = (select auth.uid()));
create policy "Users add own favourites" on public.candidate_favourites
  for insert to authenticated
  with check (user_id = (select auth.uid()) and (select private.is_live_candidate(candidate_id)));
create policy "Users remove own favourites" on public.candidate_favourites
  for delete to authenticated using (user_id = (select auth.uid()));

-- Hiring requests: customers create and read their own and may cancel;
-- recruitment staff read and update all.
grant select on public.hiring_requests to authenticated;
grant insert (customer_id, package_id, duration_months, sponsor_nationality, candidate_id,
              customer_name, customer_phone, customer_email, emirate, household_size,
              has_children, has_elderly, has_pets, preferred_start_date, requirements,
              contact_method)
  on public.hiring_requests to authenticated;
grant update (status, assigned_officer_id) on public.hiring_requests to authenticated;

create policy "Customers read own requests; staff read all" on public.hiring_requests
  for select to authenticated
  using (customer_id = (select auth.uid()) or (select private.is_recruitment_staff()));
create policy "Customers submit own requests" on public.hiring_requests
  for insert to authenticated
  with check (customer_id = (select auth.uid()));
create policy "Customers cancel own requests; staff update all" on public.hiring_requests
  for update to authenticated
  using (customer_id = (select auth.uid()) or (select private.is_recruitment_staff()))
  with check (customer_id = (select auth.uid()) or (select private.is_recruitment_staff()));

-- History: customers read visible entries of their own requests; staff read
-- all and add notes.
grant select on public.hiring_request_history to authenticated;
grant insert (request_id, status, note, is_customer_visible) on public.hiring_request_history to authenticated;
create policy "Customers read own visible history; staff read all" on public.hiring_request_history
  for select to authenticated
  using (
    (is_customer_visible and exists (
      select 1 from public.hiring_requests r
      where r.id = request_id and r.customer_id = (select auth.uid())))
    or (select private.is_recruitment_staff())
  );
create policy "Staff add history notes" on public.hiring_request_history
  for insert to authenticated with check ((select private.is_recruitment_staff()));

-- -----------------------------------------------------------------------------
-- Storage: candidate photos (public) and documents (private)
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('candidate-photos', 'candidate-photos', true, 5242880,
   array['image/jpeg', 'image/png', 'image/webp']),
  ('candidate-documents', 'candidate-documents', false, 20971520,
   array['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'video/mp4'])
on conflict (id) do nothing;

create policy "Recruitment staff upload candidate files" on storage.objects
  for insert to authenticated
  with check (bucket_id in ('candidate-photos', 'candidate-documents')
              and (select private.is_recruitment_staff()));
create policy "Recruitment staff update candidate files" on storage.objects
  for update to authenticated
  using (bucket_id in ('candidate-photos', 'candidate-documents')
         and (select private.is_recruitment_staff()))
  with check (bucket_id in ('candidate-photos', 'candidate-documents')
              and (select private.is_recruitment_staff()));
create policy "Recruitment staff delete candidate files" on storage.objects
  for delete to authenticated
  using (bucket_id in ('candidate-photos', 'candidate-documents')
         and (select private.is_recruitment_staff()));
create policy "Read candidate documents if visible or staff" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'candidate-documents'
    and (
      (select private.is_recruitment_staff())
      or exists (
        select 1 from public.candidate_documents d
        where d.storage_path = name
          and d.is_customer_visible
          and (select private.is_live_candidate(d.candidate_id))
      )
    )
  );

-- -----------------------------------------------------------------------------
-- Daily age refresh (pg_cron, where available)
-- -----------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
    perform cron.schedule('refresh-candidate-ages', '15 0 * * *',
                          'select private.refresh_candidate_ages()');
  end if;
end
$$;

-- -----------------------------------------------------------------------------
-- Packages agreed with the client (prices are set by administrators).
-- -----------------------------------------------------------------------------
insert into public.recruitment_packages
  (slug, name, description, visa_type, contract_term, min_months, max_months, month_step,
   requires_sponsor_nationality, sort_order)
values
  ('live-in-monthly', 'Full-Time Live-In Maid – Monthly',
   'Live-in maid on the company visa, hired month by month.',
   'company', 'monthly', 1, 11, 1, false, 10),
  ('live-in-yearly', 'Full-Time Live-In Maid – Yearly',
   'Live-in maid on the company visa, hired by the year.',
   'company', 'yearly', 12, 24, 12, false, 20),
  ('two-year-gcc-sponsor', '2-Year Contract – GCC Sponsor Visa',
   'Two-year contract with the maid''s visa sponsored by you (GCC nationals).',
   'sponsor', 'two_year', 24, 24, 24, true, 30);
