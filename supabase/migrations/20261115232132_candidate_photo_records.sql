-- =============================================================================
-- Golden Maids – Staff can see candidate photo records
--
-- Supabase Storage needs SELECT on storage.objects to remove (or replace) a
-- file. Candidate photos are public through their links, but staff had no
-- SELECT policy on the bucket, so replaced photos could not be deleted and
-- would pile up. Recruitment staff may now see (and so clean up) them.
-- =============================================================================

create policy "Recruitment staff see candidate photo records" on storage.objects
  for select to authenticated
  using (bucket_id = 'candidate-photos' and (select private.is_recruitment_staff()));
