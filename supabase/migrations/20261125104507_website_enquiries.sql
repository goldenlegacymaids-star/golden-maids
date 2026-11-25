-- =============================================================================
-- Note: Supabase's linter flags submit_website_enquiry as a SECURITY DEFINER
-- function callable by anon. That is intended: it is the only way in, and it
-- can only save an enquiry and return its reference.
-- Golden Maids – Website enquiries (the enquiry form on the public website)
-- =============================================================================
--   * Website visitors (not signed in) can send an enquiry through ONE door:
--     public.submit_website_enquiry(...). They cannot read, change or delete
--     any enquiry, including their own; they only get its reference number.
--   * Every field is checked and trimmed; spam is limited (same phone number
--     at most 3 times an hour, and at most 60 website enquiries an hour in all).
--   * Recruitment staff read all website enquiries, set their status and keep
--     a private note. New enquiries notify recruitment staff.
-- =============================================================================

create sequence public.website_enquiry_number_seq;

create table public.website_enquiries (
  id              uuid primary key default gen_random_uuid(),
  reference       text not null unique,
  name            text not null check (char_length(name) between 2 and 120),
  phone           text not null check (phone ~ '^\+?[0-9]{7,15}$'),
  email           text check (email is null or (char_length(email) <= 254 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  need            text check (need is null or need in ('housemaid', 'nanny', 'housekeeper', 'cook', 'driver', 'caregiver', 'not_sure')),
  nationality     text check (nationality is null or char_length(nationality) <= 60),
  emirate         text check (emirate is null or emirate in ('dubai', 'abu-dhabi', 'sharjah', 'ajman', 'ras-al-khaimah', 'fujairah', 'umm-al-quwain')),
  visa            text check (visa is null or visa in ('sponsor', 'company', 'not_sure')),
  candidate_id    uuid references public.candidates (id) on delete set null,
  candidate_code  text check (candidate_code is null or char_length(candidate_code) <= 40),
  message         text check (message is null or char_length(message) <= 1000),
  contact_method  text not null default 'whatsapp' check (contact_method in ('whatsapp', 'phone', 'email')),
  lang            text not null default 'en' check (lang in ('en', 'ar')),
  page            text check (page is null or char_length(page) <= 300),
  status          text not null default 'new' check (status in ('new', 'in_progress', 'closed')),
  handled_by      uuid references public.profiles (id) on delete set null,
  staff_note      text check (staff_note is null or char_length(staff_note) <= 2000),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on table public.website_enquiries is
  'Enquiries from the public website form. Visitors can only submit (submit_website_enquiry); recruitment staff manage them.';

create index website_enquiries_status_idx on public.website_enquiries (status, created_at desc);
create index website_enquiries_created_idx on public.website_enquiries (created_at desc);
create index website_enquiries_phone_idx on public.website_enquiries (phone, created_at desc);
create index website_enquiries_candidate_idx on public.website_enquiries (candidate_id);
create index website_enquiries_handled_by_idx on public.website_enquiries (handled_by);

create trigger website_enquiries_set_updated_at
  before update on public.website_enquiries
  for each row execute function private.set_updated_at();

-- -----------------------------------------------------------------------------
-- The only way in: submit_website_enquiry(...) → reference number
-- -----------------------------------------------------------------------------
create or replace function public.submit_website_enquiry(
  p_name text,
  p_phone text,
  p_email text default null,
  p_need text default null,
  p_nationality text default null,
  p_emirate text default null,
  p_visa text default null,
  p_candidate_code text default null,
  p_message text default null,
  p_contact_method text default 'whatsapp',
  p_lang text default 'en',
  p_page text default null,
  p_consent boolean default false
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text;
  v_code text := nullif(upper(btrim(coalesce(p_candidate_code, ''))), '');
  v_candidate uuid;
  v_reference text;
begin
  if p_consent is not true then
    raise exception 'Please agree to the privacy policy.' using errcode = '23514';
  end if;

  -- Phone: keep digits and a leading +; UAE numbers written 05x… become +9715x….
  v_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
  v_phone := regexp_replace(v_phone, '(?!^)\+', '', 'g');
  if v_phone ~ '^00' then
    v_phone := '+' || substr(v_phone, 3);
  elsif v_phone ~ '^05[0-9]{8}$' then
    v_phone := '+971' || substr(v_phone, 2);
  end if;
  if v_phone !~ '^\+?[0-9]{7,15}$' then
    raise exception 'Please enter a valid phone number.' using errcode = '23514';
  end if;

  -- Spam limits.
  if (select count(*) from public.website_enquiries e
      where e.phone = v_phone and e.created_at > now() - interval '1 hour') >= 3 then
    raise exception 'We already have your enquiry. We will contact you soon, or call us on 04 323 4393.'
      using errcode = '23514';
  end if;
  if (select count(*) from public.website_enquiries e
      where e.created_at > now() - interval '1 hour') >= 60 then
    raise exception 'We are receiving many enquiries right now. Please WhatsApp or call us on 04 323 4393.'
      using errcode = '23514';
  end if;

  -- A maid code only links to a maid who is listed.
  if v_code is not null then
    select c.id into v_candidate from public.candidates c
    where upper(c.code) = v_code and c.is_published and c.archived_at is null;
  end if;

  insert into public.website_enquiries (
    reference, name, phone, email, need, nationality, emirate, visa,
    candidate_id, candidate_code, message, contact_method, lang, page
  ) values (
    'WE-' || to_char(now() at time zone 'Asia/Dubai', 'YYYY') || '-'
      || lpad(nextval('public.website_enquiry_number_seq')::text, 6, '0'),
    btrim(coalesce(p_name, '')),
    v_phone,
    nullif(lower(btrim(coalesce(p_email, ''))), ''),
    nullif(btrim(coalesce(p_need, '')), ''),
    nullif(btrim(coalesce(p_nationality, '')), ''),
    nullif(btrim(coalesce(p_emirate, '')), ''),
    nullif(btrim(coalesce(p_visa, '')), ''),
    v_candidate,
    v_code,
    nullif(btrim(coalesce(p_message, '')), ''),
    coalesce(nullif(btrim(coalesce(p_contact_method, '')), ''), 'whatsapp'),
    coalesce(nullif(p_lang, ''), 'en'),
    left(nullif(btrim(coalesce(p_page, '')), ''), 300)
  )
  returning reference into v_reference;

  return v_reference;
end;
$$;

revoke all on function public.submit_website_enquiry(text, text, text, text, text, text, text, text, text, text, text, text, boolean)
  from public;
grant execute on function public.submit_website_enquiry(text, text, text, text, text, text, text, text, text, text, text, text, boolean)
  to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Staff are told about each new website enquiry
-- -----------------------------------------------------------------------------
create or replace function private.notify_website_enquiry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.notify_staff('recruitment', 'website_enquiry.created',
    'New website enquiry ' || new.reference,
    new.name
      || coalesce(' · ' || replace(new.need, '_', ' '), '')
      || coalesce(' · ' || new.candidate_code, ''),
    '/enquiries/website/?id=' || new.id);
  return null;
end;
$$;

revoke all on function private.notify_website_enquiry() from public, anon, authenticated;

create trigger website_enquiries_notify_staff
  after insert on public.website_enquiries
  for each row execute function private.notify_website_enquiry();

create trigger website_enquiries_audit
  after update or delete on public.website_enquiries
  for each row execute function private.log_admin_change();

-- -----------------------------------------------------------------------------
-- Row Level Security: visitors have no access to the table at all
-- -----------------------------------------------------------------------------
alter table public.website_enquiries enable row level security;
revoke all on public.website_enquiries from anon, authenticated;
grant select on public.website_enquiries to authenticated;
grant update (status, handled_by, staff_note) on public.website_enquiries to authenticated;

create policy "Recruitment staff read website enquiries" on public.website_enquiries
  for select to authenticated
  using ((select private.is_recruitment_staff()));
create policy "Recruitment staff update website enquiries" on public.website_enquiries
  for update to authenticated
  using ((select private.is_recruitment_staff()))
  with check ((select private.is_recruitment_staff()));

revoke all on sequence public.website_enquiry_number_seq from anon, authenticated;
