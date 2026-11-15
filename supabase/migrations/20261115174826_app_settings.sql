-- =============================================================================
-- Golden Maids – App settings
-- Remote switches the app reads at runtime (e.g. whether the "Send by SMS
-- instead" option is shown). Keys are created only by migrations;
-- administrators can change values (audit-logged).
-- =============================================================================

create table public.app_settings (
  key          text primary key check (key ~ '^[a-z0-9_]+(\.[a-z0-9_]+)*$'),
  value        jsonb not null,
  description  text not null default '',
  -- Public settings are readable by everyone, including guests.
  is_public    boolean not null default false,
  updated_at   timestamptz not null default now(),
  updated_by   uuid references public.profiles (id) on delete set null
);

comment on table public.app_settings is
  'Runtime app switches. Keys come from migrations; admins edit values only.';

create index app_settings_updated_by_idx on public.app_settings (updated_by);

create trigger app_settings_set_updated_at
  before update on public.app_settings
  for each row execute function private.set_updated_at();

-- Record who changed the value (cannot be forged by the client).
create or replace function private.set_app_setting_actor()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_by := (select auth.uid());
  return new;
end;
$$;

revoke all on function private.set_app_setting_actor() from public, anon;
grant execute on function private.set_app_setting_actor() to authenticated;

create trigger app_settings_set_actor
  before update on public.app_settings
  for each row execute function private.set_app_setting_actor();

-- Audit every value change.
create or replace function private.log_app_setting_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.value is distinct from old.value then
    insert into public.admin_audit_logs (actor_id, action, entity_type, entity_id, details)
    values ((select auth.uid()), 'setting.updated', 'app_setting', new.key,
            jsonb_build_object('old', old.value, 'new', new.value));
  end if;
  return new;
end;
$$;

revoke all on function private.log_app_setting_change() from public, anon, authenticated;

create trigger app_settings_audit
  after update on public.app_settings
  for each row execute function private.log_app_setting_change();

-- -----------------------------------------------------------------------------
-- Row Level Security
-- -----------------------------------------------------------------------------
alter table public.app_settings enable row level security;

revoke all on public.app_settings from anon, authenticated;
grant select on public.app_settings to anon, authenticated;
-- Admins may change only the value.
grant update (value) on public.app_settings to authenticated;

create policy "Guests read public settings"
  on public.app_settings for select
  to anon
  using (is_public);

create policy "Users read public settings; admins read all"
  on public.app_settings for select
  to authenticated
  using (is_public or (select private.is_admin()));

create policy "Admins update setting values"
  on public.app_settings for update
  to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

-- -----------------------------------------------------------------------------
-- Initial settings
-- -----------------------------------------------------------------------------
insert into public.app_settings (key, value, description, is_public) values
  ('auth.sms_fallback_enabled', 'false'::jsonb,
   'Show "Send by SMS instead" on the verification screen. Enable only once an SMS provider with a registered UAE Sender ID is configured.',
   true);
