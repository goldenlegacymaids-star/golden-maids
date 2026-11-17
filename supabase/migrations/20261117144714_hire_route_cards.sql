-- =============================================================================
-- Golden Maids – Photos for the "Hire a Maid" cards on Home
-- =============================================================================
-- One row per visa route (GCC Sponsor Visa, Company Visa) holding the path of
-- its photo in the public app-media bucket (uploaded by administrators on the
-- staff website, Photos page). Everyone can read them; only administrators
-- can change the photo. Without a photo the app shows the brand colour.

create table public.hire_route_cards (
  id          uuid primary key default gen_random_uuid(),
  visa_type   text not null unique check (visa_type in ('sponsor', 'company')),
  image_path  text check (image_path is null or char_length(image_path) <= 300),
  updated_at  timestamptz not null default now()
);

comment on table public.hire_route_cards is
  'Photos of the Hire a Maid cards on the app''s Home screen (paths in app-media).';

create trigger hire_route_cards_set_updated_at
  before update on public.hire_route_cards
  for each row execute function private.set_updated_at();

create trigger hire_route_cards_audit
  after insert or update or delete on public.hire_route_cards
  for each row execute function private.log_admin_change();

insert into public.hire_route_cards (visa_type) values ('sponsor'), ('company');

alter table public.hire_route_cards enable row level security;

revoke all on public.hire_route_cards from anon, authenticated;
grant select on public.hire_route_cards to anon, authenticated;
grant update (image_path) on public.hire_route_cards to authenticated;

create policy "Everyone reads the hire cards"
  on public.hire_route_cards for select to anon, authenticated
  using (true);

create policy "Admins change the hire card photos"
  on public.hire_route_cards for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));
