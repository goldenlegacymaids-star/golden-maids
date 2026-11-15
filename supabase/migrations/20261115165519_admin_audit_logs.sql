-- =============================================================================
-- Golden Maids – Admin audit log
-- Append-only record of administrative actions. Entries are written only by
-- database triggers; nobody can edit or delete them through the API.
-- =============================================================================

create table public.admin_audit_logs (
  id           bigint generated always as identity primary key,
  actor_id     uuid references public.profiles (id) on delete set null,
  action       text not null check (action ~ '^[a-z_]+\.[a-z_]+$'),
  entity_type  text not null,
  entity_id    text,
  details      jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now()
);

comment on table public.admin_audit_logs is
  'Append-only audit trail of administrative actions, written by triggers.';

create index admin_audit_logs_created_at_idx on public.admin_audit_logs (created_at desc);
create index admin_audit_logs_actor_id_idx   on public.admin_audit_logs (actor_id);
create index admin_audit_logs_entity_idx     on public.admin_audit_logs (entity_type, entity_id);

alter table public.admin_audit_logs enable row level security;

revoke all on public.admin_audit_logs from anon;
revoke insert, update, delete, truncate on public.admin_audit_logs from authenticated;

create policy "Admins read audit logs"
  on public.admin_audit_logs for select
  to authenticated
  using ((select private.is_admin()));

-- -----------------------------------------------------------------------------
-- Log every role grant and removal (except the automatic Customer role
-- given at sign-up).
-- -----------------------------------------------------------------------------
create or replace function private.log_user_role_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
begin
  if tg_op = 'INSERT' then
    if new.role_id = 'customer' and v_actor is null then
      return new;
    end if;
    insert into public.admin_audit_logs (actor_id, action, entity_type, entity_id, details)
    values (v_actor, 'role.granted', 'user', new.user_id::text,
            jsonb_build_object('role', new.role_id));
    return new;
  end if;

  insert into public.admin_audit_logs (actor_id, action, entity_type, entity_id, details)
  values (v_actor, 'role.revoked', 'user', old.user_id::text,
          jsonb_build_object('role', old.role_id));
  return old;
end;
$$;

revoke all on function private.log_user_role_change() from public, anon, authenticated;

create trigger user_roles_audit
  after insert or delete on public.user_roles
  for each row execute function private.log_user_role_change();
