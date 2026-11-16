-- =============================================================================
-- Golden Maids – Processing account deletion requests; admins manage app images
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Records kept after an account is deleted
-- -----------------------------------------------------------------------------
-- Bookings and hiring requests stay as business records without the customer.
-- New rows still need a customer: the insert policies require
-- customer_id = auth.uid().
alter table public.bookings alter column customer_id drop not null;
alter table public.hiring_requests alter column customer_id drop not null;

-- -----------------------------------------------------------------------------
-- public.process_account_deletion(request id, note)
-- -----------------------------------------------------------------------------
-- Administrators only. Deletes the customer's sign-in and personal data:
--   - profile, roles, saved addresses, saved maids and enquiries (these are
--     removed with the profile);
--   - name, phone, email, address details and free-text notes on their
--     bookings and hiring requests, which are kept, unlinked from the account.
-- Refused while the customer has upcoming or active bookings or open hiring
-- requests, or holds staff roles. The request is marked completed and the
-- deletion is written to the audit log.
create or replace function public.process_account_deletion(
  p_request_id uuid,
  p_note text default ''
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

revoke all on function public.process_account_deletion(uuid, text) from public, anon;
grant execute on function public.process_account_deletion(uuid, text) to authenticated;

comment on function public.process_account_deletion(uuid, text) is
  'Administrators: delete a customer''s account for a pending deletion request, keeping anonymised bookings and hiring requests.';

-- -----------------------------------------------------------------------------
-- Admins can replace and remove app images (service, category, banner photos)
-- -----------------------------------------------------------------------------
-- Removing a file needs read access to it; the bucket is public, so this only
-- lets admins list and remove files through the API.
create policy "Admins read app media"
  on storage.objects for select to authenticated
  using (bucket_id = 'app-media' and (select private.is_admin()));
