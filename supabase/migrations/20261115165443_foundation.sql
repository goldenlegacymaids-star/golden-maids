-- =============================================================================
-- Golden Maids – Foundation
-- Private schema for internal helper functions (not exposed through the API)
-- and a shared trigger to maintain updated_at columns.
-- =============================================================================

create schema if not exists private;

revoke all on schema private from public;
-- Signed-in users need USAGE so RLS policies can call private role checks.
-- The schema is NOT exposed through the Supabase API, so these functions
-- cannot be called directly from the app.
grant usage on schema private to authenticated;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function private.set_updated_at() from public;
