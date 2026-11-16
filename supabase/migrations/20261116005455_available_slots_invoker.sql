-- =============================================================================
-- Golden Maids – available_slots runs with the caller's rights
--
-- Same behaviour as before. The public function no longer needs elevated
-- rights: guests and customers read the booking settings and active
-- services themselves (as Row Level Security allows), and only the internal
-- capacity check (private schema, not reachable through the API) reads
-- bookings with elevated rights – returning true/false, never booking data.
-- =============================================================================

alter function public.available_slots(uuid, date, integer) security invoker;

grant execute on function private.booking_capacity_ok(uuid, timestamptz, timestamptz, uuid)
  to anon, authenticated;
