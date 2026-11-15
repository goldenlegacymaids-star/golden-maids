-- =============================================================================
-- Golden Maids – Status changes with a note, as one timeline entry
--
-- Staff change a hiring request's status (optionally with a note, shown to
-- the customer or kept internal) through public.update_hiring_status().
-- The existing timeline trigger now records that note on the same entry, so
-- the customer never sees the status twice. The function runs with the
-- caller's own rights (security invoker): Row Level Security and column
-- privileges still apply, and only recruitment staff may call it.
-- =============================================================================

-- Timeline trigger: include the note / visibility passed by the function.
create or replace function private.record_hiring_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.hiring_request_history (request_id, status, note, is_customer_visible, created_by)
    values (
      new.id,
      new.status,
      coalesce(current_setting('golden_maids.status_note', true), ''),
      coalesce(nullif(current_setting('golden_maids.status_note_visible', true), '')::boolean, true),
      (select auth.uid())
    );
  end if;
  return new;
end;
$$;

revoke all on function private.record_hiring_status() from public, anon, authenticated;

-- Staff: change status (with an optional note) or add a note only.
create or replace function public.update_hiring_status(
  p_request_id uuid,
  p_status text,
  p_note text default '',
  p_customer_visible boolean default true
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_note text := btrim(coalesce(p_note, ''));
  v_current text;
begin
  if not (select private.is_recruitment_staff()) then
    raise exception 'Only recruitment staff can update hiring requests.' using errcode = '42501';
  end if;

  if p_status not in ('submitted', 'under_review', 'shortlisted', 'interview_scheduled',
                      'offer_accepted', 'visa_processing', 'completed', 'cancelled', 'rejected') then
    raise exception 'Unknown status.' using errcode = '23514';
  end if;

  if char_length(v_note) > 2000 then
    raise exception 'Please keep the note under 2000 characters.' using errcode = '23514';
  end if;

  select r.status into v_current from public.hiring_requests r where r.id = p_request_id;
  if not found then
    raise exception 'This request no longer exists.' using errcode = 'P0002';
  end if;

  if v_current = p_status then
    -- Note only (no status change).
    if v_note = '' then
      return;
    end if;
    insert into public.hiring_request_history (request_id, status, note, is_customer_visible)
    values (p_request_id, p_status, v_note, coalesce(p_customer_visible, true));
    return;
  end if;

  -- Read by the timeline trigger for this transaction only.
  perform set_config('golden_maids.status_note', v_note, true);
  perform set_config('golden_maids.status_note_visible',
                     case when coalesce(p_customer_visible, true) then 'true' else 'false' end, true);

  update public.hiring_requests set status = p_status where id = p_request_id;

  perform set_config('golden_maids.status_note', '', true);
  perform set_config('golden_maids.status_note_visible', '', true);
end;
$$;

revoke all on function public.update_hiring_status(uuid, text, text, boolean) from public, anon;
grant execute on function public.update_hiring_status(uuid, text, text, boolean) to authenticated;
