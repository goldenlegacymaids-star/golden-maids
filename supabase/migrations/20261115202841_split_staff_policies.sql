-- =============================================================================
-- Golden Maids – Split "for all" staff policies into insert/update/delete.
-- The read policies already allow recruitment staff, so the "for all"
-- policies made Postgres evaluate two SELECT policies per row
-- (advisor: multiple_permissive_policies). Access is unchanged.
-- =============================================================================

-- candidate_skills
drop policy "Staff manage skills" on public.candidate_skills;
create policy "Staff add skills" on public.candidate_skills
  for insert to authenticated with check ((select private.is_recruitment_staff()));
create policy "Staff update skills" on public.candidate_skills
  for update to authenticated
  using ((select private.is_recruitment_staff())) with check ((select private.is_recruitment_staff()));
create policy "Staff delete skills" on public.candidate_skills
  for delete to authenticated using ((select private.is_recruitment_staff()));

-- candidate_languages
drop policy "Staff manage languages" on public.candidate_languages;
create policy "Staff add languages" on public.candidate_languages
  for insert to authenticated with check ((select private.is_recruitment_staff()));
create policy "Staff update languages" on public.candidate_languages
  for update to authenticated
  using ((select private.is_recruitment_staff())) with check ((select private.is_recruitment_staff()));
create policy "Staff delete languages" on public.candidate_languages
  for delete to authenticated using ((select private.is_recruitment_staff()));

-- candidate_experience
drop policy "Staff manage experience" on public.candidate_experience;
create policy "Staff add experience" on public.candidate_experience
  for insert to authenticated with check ((select private.is_recruitment_staff()));
create policy "Staff update experience" on public.candidate_experience
  for update to authenticated
  using ((select private.is_recruitment_staff())) with check ((select private.is_recruitment_staff()));
create policy "Staff delete experience" on public.candidate_experience
  for delete to authenticated using ((select private.is_recruitment_staff()));

-- candidate_packages
drop policy "Staff manage candidate packages" on public.candidate_packages;
create policy "Staff add candidate packages" on public.candidate_packages
  for insert to authenticated with check ((select private.is_recruitment_staff()));
create policy "Staff update candidate packages" on public.candidate_packages
  for update to authenticated
  using ((select private.is_recruitment_staff())) with check ((select private.is_recruitment_staff()));
create policy "Staff delete candidate packages" on public.candidate_packages
  for delete to authenticated using ((select private.is_recruitment_staff()));

-- candidate_documents
drop policy "Staff manage documents" on public.candidate_documents;
create policy "Staff add documents" on public.candidate_documents
  for insert to authenticated with check ((select private.is_recruitment_staff()));
create policy "Staff update documents" on public.candidate_documents
  for update to authenticated
  using ((select private.is_recruitment_staff())) with check ((select private.is_recruitment_staff()));
create policy "Staff delete documents" on public.candidate_documents
  for delete to authenticated using ((select private.is_recruitment_staff()));
