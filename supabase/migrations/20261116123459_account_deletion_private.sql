-- =============================================================================
-- Golden Maids – Tidy-up: account deletion runs in the private schema
-- =============================================================================
-- The work is done by private.process_account_deletion (SECURITY DEFINER, not
-- reachable through the API). public.process_account_deletion stays the entry
-- point the staff website calls; it runs with the caller's own rights. The
-- behaviour is unchanged: only administrators can delete accounts.

create or replace function private.process_account_deletion(
  p_request_id uuid,
  p_note text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := (select auth.uid());
  v_user uuid;
  v_status text;
  v_bookings integer;
  v_hiring integer;
begin
  if not (select private.is_admin()) then
    raise exception 'Only administrators can delete accounts.' using errcode = '42501';
  end if;
  if char_length(coalesce(p_note, '')) > 1000 then
    raise exception 'Please keep the note under 1000 characters.' using errcode = '23514';
  end if;

  select user_id, status into v_user, v_status
  from public.account_deletion_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'This request was not found.' using errcode = 'P0002';
  end if;
  if v_status <> 'pending' or v_user is null then
    raise exception 'This request is no longer pending.' using errcode = '23514';
  end if;
  if v_user = v_admin then
    raise exception 'You cannot delete your own account here.' using errcode = '42501';
  end if;
  if exists (select 1 from public.user_roles
             where user_id = v_user and role_id <> 'customer') then
    raise exception 'This account has staff roles. Remove them on the Staff roles page first.'
      using errcode = '23514';
  end if;
  if exists (select 1 from public.bookings
             where customer_id = v_user
               and status in ('pending', 'confirmed', 'provider_assigned', 'on_the_way', 'in_progress')) then
    raise exception 'The customer has upcoming or active bookings. Complete or cancel them first.'
      using errcode = '23514';
  end if;
  if exists (select 1 from public.hiring_requests
             where customer_id = v_user
               and status not in ('completed', 'cancelled', 'rejected')) then
    raise exception 'The customer has open hiring requests. Complete, cancel or reject them first.'
      using errcode = '23514';
  end if;

  -- Keep the records, without the person.
  update public.bookings
  set customer_id = null,
      customer_name = 'Deleted customer',
      customer_phone = 'Removed',
      address_id = null,
      building = 'Removed',
      apartment = '',
      address_notes = '',
      instructions = ''
  where customer_id = v_user;
  get diagnostics v_bookings = row_count;

  update public.hiring_requests
  set customer_id = null,
      customer_name = 'Deleted customer',
      customer_phone = 'Removed',
      customer_email = null,
      requirements = ''
  where customer_id = v_user;
  get diagnostics v_hiring = row_count;

  update public.account_deletion_requests
  set status = 'completed',
      staff_note = coalesce(p_note, '')
  where id = p_request_id;

  insert into public.admin_audit_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'account.deleted', 'profiles', v_user::text,
          jsonb_build_object('request_id', p_request_id,
                             'bookings_kept', v_bookings,
                             'hiring_requests_kept', v_hiring));

  -- Removes the sign-in; the profile and everything linked to it follow.
  delete from auth.users where id = v_user;
end;
$$;

revoke all on function private.process_account_deletion(uuid, text) from public, anon;
grant execute on function private.process_account_deletion(uuid, text) to authenticated;

drop function public.process_account_deletion(uuid, text);

create function public.process_account_deletion(
  p_request_id uuid,
  p_note text default ''
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.process_account_deletion(p_request_id, p_note);
$$;

revoke all on function public.process_account_deletion(uuid, text) from public, anon;
grant execute on function public.process_account_deletion(uuid, text) to authenticated;

comment on function public.process_account_deletion(uuid, text) is
  'Administrators: delete a customer''s account for a pending deletion request, keeping anonymised bookings and hiring requests.';
