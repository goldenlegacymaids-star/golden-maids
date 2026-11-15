-- =============================================================================
-- Golden Maids – Save a candidate in one step (staff website)
--
-- public.save_candidate() creates or updates a candidate together with the
-- private details, skills, languages, work history and packages, in a single
-- transaction: either everything is saved or nothing is. It runs with the
-- caller's own rights (security invoker), so Row Level Security, column
-- privileges, check constraints and audit triggers all still apply, and it
-- refuses anyone who is not recruitment staff.
--
-- Photos and documents are uploaded separately (Storage), as before.
-- =============================================================================

create or replace function public.save_candidate(
  p_candidate  jsonb,           -- public fields; "id" null for a new candidate
  p_private    jsonb,           -- full_name, date_of_birth, passport_number, internal_notes
  p_skills     text[]  default '{}',
  p_languages  jsonb   default '[]',   -- [{language, proficiency}]
  p_experience jsonb   default '[]',   -- [{country, role, start_year, end_year, description}]
  p_packages   uuid[]  default '{}'
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid := nullif(p_candidate->>'id', '')::uuid;
  v_archived boolean := coalesce((p_candidate->>'archived')::boolean, false);
begin
  if not (select private.is_recruitment_staff()) then
    raise exception 'Only recruitment staff can save candidates.' using errcode = '42501';
  end if;

  if coalesce(btrim(p_private->>'full_name'), '') = '' or (p_private->>'date_of_birth') is null then
    raise exception 'Full name and date of birth are required.' using errcode = '23514';
  end if;

  if v_id is null then
    insert into public.candidates (
      nationality, designation, accommodation, years_experience, highest_qualification,
      religion, marital_status, expected_salary, availability_status, available_from, bio,
      show_full_name, is_published, is_featured, consent_obtained_at, archived_at
    ) values (
      p_candidate->>'nationality',
      coalesce(nullif(btrim(p_candidate->>'designation'), ''), 'Housemaid'),
      coalesce(p_candidate->>'accommodation', 'live_in'),
      coalesce((p_candidate->>'years_experience')::integer, 0),
      nullif(btrim(p_candidate->>'highest_qualification'), ''),
      nullif(p_candidate->>'religion', ''),
      nullif(p_candidate->>'marital_status', ''),
      (p_candidate->>'expected_salary')::numeric,
      coalesce(p_candidate->>'availability_status', 'available'),
      (p_candidate->>'available_from')::date,
      coalesce(btrim(p_candidate->>'bio'), ''),
      coalesce((p_candidate->>'show_full_name')::boolean, false),
      coalesce((p_candidate->>'is_published')::boolean, false),
      coalesce((p_candidate->>'is_featured')::boolean, false),
      (p_candidate->>'consent_obtained_at')::timestamptz,
      case when v_archived then now() end
    )
    returning id into v_id;
  else
    update public.candidates c set
      nationality           = p_candidate->>'nationality',
      designation           = coalesce(nullif(btrim(p_candidate->>'designation'), ''), 'Housemaid'),
      accommodation         = coalesce(p_candidate->>'accommodation', 'live_in'),
      years_experience      = coalesce((p_candidate->>'years_experience')::integer, 0),
      highest_qualification = nullif(btrim(p_candidate->>'highest_qualification'), ''),
      religion              = nullif(p_candidate->>'religion', ''),
      marital_status        = nullif(p_candidate->>'marital_status', ''),
      expected_salary       = (p_candidate->>'expected_salary')::numeric,
      availability_status   = coalesce(p_candidate->>'availability_status', 'available'),
      available_from        = (p_candidate->>'available_from')::date,
      bio                   = coalesce(btrim(p_candidate->>'bio'), ''),
      show_full_name        = coalesce((p_candidate->>'show_full_name')::boolean, false),
      is_published          = coalesce((p_candidate->>'is_published')::boolean, false),
      is_featured           = coalesce((p_candidate->>'is_featured')::boolean, false),
      consent_obtained_at   = (p_candidate->>'consent_obtained_at')::timestamptz,
      archived_at           = case when v_archived then coalesce(c.archived_at, now()) end
    where c.id = v_id;
    if not found then
      raise exception 'This candidate no longer exists.' using errcode = 'P0002';
    end if;
  end if;

  -- Private details (also keeps the public age and allowed name in sync).
  insert into public.candidate_private_details (candidate_id, full_name, date_of_birth, passport_number, internal_notes)
  values (
    v_id,
    btrim(p_private->>'full_name'),
    (p_private->>'date_of_birth')::date,
    nullif(btrim(p_private->>'passport_number'), ''),
    coalesce(p_private->>'internal_notes', '')
  )
  on conflict (candidate_id) do update set
    full_name       = excluded.full_name,
    date_of_birth   = excluded.date_of_birth,
    passport_number = excluded.passport_number,
    internal_notes  = excluded.internal_notes;

  -- Lists are replaced as a whole.
  delete from public.candidate_skills where candidate_id = v_id;
  insert into public.candidate_skills (candidate_id, skill)
  select distinct v_id, s from unnest(coalesce(p_skills, '{}')) as s;

  delete from public.candidate_languages where candidate_id = v_id;
  insert into public.candidate_languages (candidate_id, language, proficiency)
  select v_id, btrim(l.language), coalesce(l.proficiency, 'good')
  from jsonb_to_recordset(coalesce(p_languages, '[]')) as l(language text, proficiency text);

  delete from public.candidate_experience where candidate_id = v_id;
  insert into public.candidate_experience (candidate_id, country, role, start_year, end_year, description)
  select v_id, btrim(e.country), btrim(e.role), e.start_year, e.end_year, coalesce(e.description, '')
  from jsonb_to_recordset(coalesce(p_experience, '[]'))
    as e(country text, role text, start_year integer, end_year integer, description text);

  delete from public.candidate_packages where candidate_id = v_id;
  insert into public.candidate_packages (candidate_id, package_id)
  select distinct v_id, p from unnest(coalesce(p_packages, '{}')) as p;

  return v_id;
end;
$$;

revoke all on function public.save_candidate(jsonb, jsonb, text[], jsonb, jsonb, uuid[]) from public, anon;
grant execute on function public.save_candidate(jsonb, jsonb, text[], jsonb, jsonb, uuid[]) to authenticated;
