-- =============================================================================
-- Golden Maids – Health check
-- Lets the app confirm it can reach the database. Returns no user data.
-- =============================================================================

create or replace function public.health_check()
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object('status', 'ok', 'server_time', now());
$$;

revoke all on function public.health_check() from public;
grant execute on function public.health_check() to anon, authenticated;
