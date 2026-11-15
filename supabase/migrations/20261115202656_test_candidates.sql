-- =============================================================================
-- Golden Maids – TEST candidates (development only)
-- Three clearly marked test records (is_test = true) with illustrated avatars.
-- ⚠️ Delete before launch:  delete from public.candidates where is_test;
-- =============================================================================

do $$
declare
  v_monthly uuid := (select id from public.recruitment_packages where slug = 'live-in-monthly');
  v_yearly  uuid := (select id from public.recruitment_packages where slug = 'live-in-yearly');
  v_gcc     uuid := (select id from public.recruitment_packages where slug = 'two-year-gcc-sponsor');
  v_id      uuid;
begin
  -- Kenya
  insert into public.candidates (show_full_name, photo_path, nationality, designation,
    years_experience, highest_qualification, religion, marital_status, expected_salary,
    available_from, bio, is_published, is_featured, is_test, consent_obtained_at)
  values (true, 'test/test-candidate-kenya.png', 'Kenya', 'Housemaid', 6,
    'Secondary school', 'Christian', 'Single', 1800, current_date,
    'TEST PROFILE. Hard-working housemaid with Gulf experience in villas and apartments.',
    true, true, true, now())
  returning id into v_id;
  insert into public.candidate_private_details (candidate_id, full_name, date_of_birth)
  values (v_id, 'Wanjiru Kamau', date '1992-04-12');
  insert into public.candidate_skills (candidate_id, skill) values
    (v_id, 'cleaning'), (v_id, 'cooking'), (v_id, 'laundry'), (v_id, 'ironing');
  insert into public.candidate_languages (candidate_id, language, proficiency) values
    (v_id, 'English', 'fluent'), (v_id, 'Swahili', 'fluent'), (v_id, 'Arabic', 'basic');
  insert into public.candidate_experience (candidate_id, country, role, start_year, end_year) values
    (v_id, 'Saudi Arabia', 'Housemaid', 2018, 2021),
    (v_id, 'United Arab Emirates', 'Housemaid', 2021, 2024);
  insert into public.candidate_packages (candidate_id, package_id) values
    (v_id, v_monthly), (v_id, v_yearly), (v_id, v_gcc);

  -- Myanmar
  insert into public.candidates (show_full_name, photo_path, nationality, designation,
    years_experience, highest_qualification, religion, marital_status, expected_salary,
    available_from, bio, is_published, is_featured, is_test, consent_obtained_at)
  values (true, 'test/test-candidate-myanmar.png', 'Myanmar', 'Nanny', 4,
    'Secondary school', 'Buddhist', 'Single', 1600, current_date + 14,
    'TEST PROFILE. Caring nanny experienced with toddlers and school-age children.',
    true, true, true, now())
  returning id into v_id;
  insert into public.candidate_private_details (candidate_id, full_name, date_of_birth)
  values (v_id, 'Thandar Aung', date '1995-09-03');
  insert into public.candidate_skills (candidate_id, skill) values
    (v_id, 'childcare'), (v_id, 'cleaning'), (v_id, 'cooking');
  insert into public.candidate_languages (candidate_id, language, proficiency) values
    (v_id, 'Burmese', 'fluent'), (v_id, 'English', 'good');
  insert into public.candidate_experience (candidate_id, country, role, start_year, end_year) values
    (v_id, 'Malaysia', 'Nanny', 2019, 2022),
    (v_id, 'Singapore', 'Nanny', 2022, 2024);
  insert into public.candidate_packages (candidate_id, package_id) values
    (v_id, v_monthly), (v_id, v_yearly);

  -- Philippines
  insert into public.candidates (show_full_name, photo_path, nationality, designation,
    years_experience, highest_qualification, religion, marital_status, expected_salary,
    available_from, bio, is_published, is_featured, is_test, consent_obtained_at)
  values (true, 'test/test-candidate-philippines.png', 'Philippines', 'Housekeeper', 9,
    'College diploma', 'Christian', 'Married', 2200, current_date,
    'TEST PROFILE. Experienced housekeeper, confident with cooking and elderly care.',
    true, true, true, now())
  returning id into v_id;
  insert into public.candidate_private_details (candidate_id, full_name, date_of_birth)
  values (v_id, 'Maria Santos', date '1988-01-20');
  insert into public.candidate_skills (candidate_id, skill) values
    (v_id, 'household_management'), (v_id, 'cleaning'), (v_id, 'cooking'),
    (v_id, 'elderly_care'), (v_id, 'laundry');
  insert into public.candidate_languages (candidate_id, language, proficiency) values
    (v_id, 'English', 'fluent'), (v_id, 'Tagalog', 'fluent'), (v_id, 'Arabic', 'good');
  insert into public.candidate_experience (candidate_id, country, role, start_year, end_year) values
    (v_id, 'Kuwait', 'Housekeeper', 2014, 2018),
    (v_id, 'United Arab Emirates', 'Housekeeper', 2018, 2024);
  insert into public.candidate_packages (candidate_id, package_id) values
    (v_id, v_monthly), (v_id, v_yearly), (v_id, v_gcc);
end
$$;
