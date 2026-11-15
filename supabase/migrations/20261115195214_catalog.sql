-- =============================================================================
-- Golden Maids – Service catalogue, promotions and public media
-- Public (guest-readable) marketing content. Only administrators can change
-- it; every change made through the app/dashboard API is audit-logged.
-- Prices and offers are set by administrators (null = "Price on request").
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Generic audit trigger for admin-managed tables.
-- Logs changes made by signed-in users (API). Migrations/seeds (no user) are
-- not logged.
-- -----------------------------------------------------------------------------
create or replace function private.log_admin_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_row   jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
begin
  if v_actor is not null then
    insert into public.admin_audit_logs (actor_id, action, entity_type, entity_id, details)
    values (
      v_actor,
      tg_table_name || '.' || case tg_op
        when 'INSERT' then 'created'
        when 'UPDATE' then 'updated'
        else 'deleted'
      end,
      tg_table_name,
      v_row ->> 'id',
      case when tg_op = 'UPDATE'
        then jsonb_build_object('old', to_jsonb(old), 'new', to_jsonb(new))
        else v_row
      end
    );
  end if;
  return coalesce(new, old);
end;
$$;

revoke all on function private.log_admin_change() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- service_categories
-- -----------------------------------------------------------------------------
create table public.service_categories (
  id           uuid primary key default gen_random_uuid(),
  slug         text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name         text not null check (char_length(name) between 1 and 80),
  description  text not null default '' check (char_length(description) <= 500),
  -- Icon key understood by the app (e.g. 'cleaning', 'nurse').
  icon         text not null default 'service' check (icon ~ '^[a-z_]+$'),
  -- Path inside the public 'app-media' storage bucket.
  image_path   text check (image_path is null or char_length(image_path) <= 300),
  sort_order   integer not null default 0,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.service_categories is
  'Home-service categories shown on the home screen. Admin-managed.';

create index service_categories_active_order_idx
  on public.service_categories (is_active, sort_order);

create trigger service_categories_set_updated_at
  before update on public.service_categories
  for each row execute function private.set_updated_at();

create trigger service_categories_audit
  after insert or update or delete on public.service_categories
  for each row execute function private.log_admin_change();

-- -----------------------------------------------------------------------------
-- services
-- -----------------------------------------------------------------------------
create table public.services (
  id                 uuid primary key default gen_random_uuid(),
  category_id        uuid not null references public.service_categories (id) on delete restrict,
  slug               text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name               text not null check (char_length(name) between 1 and 120),
  short_description  text not null default '' check (char_length(short_description) <= 160),
  description        text not null default '' check (char_length(description) <= 4000),
  requirements       text not null default '' check (char_length(requirements) <= 2000),
  image_path         text check (image_path is null or char_length(image_path) <= 300),
  -- Set by administrators. Null price = "Price on request".
  base_price         numeric(10, 2) check (base_price is null or base_price >= 0),
  price_unit         text check (price_unit in ('per_hour', 'per_visit', 'per_month', 'fixed')),
  duration_minutes   integer check (duration_minutes is null or duration_minutes > 0),
  is_popular         boolean not null default false,
  sort_order         integer not null default 0,
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint services_price_has_unit check (base_price is null or price_unit is not null)
);

comment on table public.services is
  'Bookable home services. Prices are admin-managed; null price means "Price on request".';

create index services_category_id_idx on public.services (category_id);
create index services_active_popular_idx on public.services (is_active, is_popular, sort_order);

create trigger services_set_updated_at
  before update on public.services
  for each row execute function private.set_updated_at();

create trigger services_audit
  after insert or update or delete on public.services
  for each row execute function private.log_admin_change();

-- -----------------------------------------------------------------------------
-- promotions (home-screen banners and offers)
-- -----------------------------------------------------------------------------
create table public.promotions (
  id                uuid primary key default gen_random_uuid(),
  title             text not null check (char_length(title) between 1 and 60),
  subtitle          text not null default '' check (char_length(subtitle) <= 120),
  cta_label         text not null default '' check (char_length(cta_label) <= 30),
  -- What the button opens: nothing, a category (slug) or a service (slug).
  target_type       text not null default 'none' check (target_type in ('none', 'category', 'service')),
  target_value      text,
  -- Offer percentage shown on the banner; set by administrators.
  discount_percent  numeric(5, 2) check (discount_percent is null or (discount_percent > 0 and discount_percent <= 100)),
  image_path        text check (image_path is null or char_length(image_path) <= 300),
  starts_at         timestamptz,
  ends_at           timestamptz,
  sort_order        integer not null default 0,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint promotions_dates check (starts_at is null or ends_at is null or ends_at > starts_at),
  constraint promotions_target check ((target_type = 'none') = (target_value is null))
);

comment on table public.promotions is
  'Home-screen banners/offers. Shown only while active and within their dates. Admin-managed.';

create index promotions_active_order_idx on public.promotions (is_active, sort_order);

create trigger promotions_set_updated_at
  before update on public.promotions
  for each row execute function private.set_updated_at();

create trigger promotions_audit
  after insert or update or delete on public.promotions
  for each row execute function private.log_admin_change();

-- -----------------------------------------------------------------------------
-- Row Level Security: everyone reads live content; admins manage everything.
-- -----------------------------------------------------------------------------
alter table public.service_categories enable row level security;
alter table public.services           enable row level security;
alter table public.promotions         enable row level security;

revoke all on public.service_categories, public.services, public.promotions from anon;
grant select on public.service_categories, public.services, public.promotions to anon;
revoke truncate on public.service_categories, public.services, public.promotions from authenticated;

-- service_categories
create policy "Guests read active categories"
  on public.service_categories for select to anon
  using (is_active);
create policy "Users read active categories; admins read all"
  on public.service_categories for select to authenticated
  using (is_active or (select private.is_admin()));
create policy "Admins add categories"
  on public.service_categories for insert to authenticated
  with check ((select private.is_admin()));
create policy "Admins update categories"
  on public.service_categories for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));
create policy "Admins delete categories"
  on public.service_categories for delete to authenticated
  using ((select private.is_admin()));

-- services (a service is visible only if its category is active too)
create policy "Guests read active services"
  on public.services for select to anon
  using (
    is_active
    and exists (select 1 from public.service_categories c
                where c.id = category_id and c.is_active)
  );
create policy "Users read active services; admins read all"
  on public.services for select to authenticated
  using (
    (is_active and exists (select 1 from public.service_categories c
                           where c.id = category_id and c.is_active))
    or (select private.is_admin())
  );
create policy "Admins add services"
  on public.services for insert to authenticated
  with check ((select private.is_admin()));
create policy "Admins update services"
  on public.services for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));
create policy "Admins delete services"
  on public.services for delete to authenticated
  using ((select private.is_admin()));

-- promotions (live = active and within dates)
create policy "Guests read live promotions"
  on public.promotions for select to anon
  using (
    is_active
    and (starts_at is null or starts_at <= now())
    and (ends_at is null or ends_at > now())
  );
create policy "Users read live promotions; admins read all"
  on public.promotions for select to authenticated
  using (
    (is_active
     and (starts_at is null or starts_at <= now())
     and (ends_at is null or ends_at > now()))
    or (select private.is_admin())
  );
create policy "Admins add promotions"
  on public.promotions for insert to authenticated
  with check ((select private.is_admin()));
create policy "Admins update promotions"
  on public.promotions for update to authenticated
  using ((select private.is_admin())) with check ((select private.is_admin()));
create policy "Admins delete promotions"
  on public.promotions for delete to authenticated
  using ((select private.is_admin()));

-- -----------------------------------------------------------------------------
-- Public media bucket (category, service and banner images only – never
-- personal documents). Anyone can view; only admins can upload or change.
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('app-media', 'app-media', true, 5242880,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy "Admins upload app media"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'app-media' and (select private.is_admin()));
create policy "Admins update app media"
  on storage.objects for update to authenticated
  using (bucket_id = 'app-media' and (select private.is_admin()))
  with check (bucket_id = 'app-media' and (select private.is_admin()));
create policy "Admins delete app media"
  on storage.objects for delete to authenticated
  using (bucket_id = 'app-media' and (select private.is_admin()));

-- -----------------------------------------------------------------------------
-- Initial catalogue (agreed with the client). Prices are left for admins.
-- -----------------------------------------------------------------------------
insert into public.service_categories (slug, name, description, icon, sort_order) values
  ('general-cleaning', 'General Cleaning', 'Regular home cleaning and move-in / move-out cleaning.', 'cleaning', 10),
  ('deep-cleaning', 'Deep Cleaning', 'Thorough top-to-bottom cleaning, including furniture.', 'deep_cleaning', 20),
  ('hourly-maid', 'Hourly Maid', 'Book a maid by the hour, when you need one.', 'hourly', 30),
  ('maid-services', 'Maid Services', 'Daily, weekly, temporary and regular housekeeping.', 'maid', 40),
  ('nanny-baby-care', 'Nanny & Baby Care', 'Nannies, babysitters and baby care at home.', 'baby', 50),
  ('elderly-care', 'Elderly Care', 'Caring support for elderly family members at home.', 'elderly', 60),
  ('home-caregiver', 'Home Caregiver', 'Caregivers for daily living support at home.', 'caregiver', 70),
  ('nurse', 'Nurse', 'Nursing care at home.', 'nurse', 80),
  ('home-driver', 'Home Driver', 'Professional drivers for your family.', 'driver', 90),
  ('pet-care', 'Pet Care', 'Feeding, walking and caring for your pets.', 'pet', 100),
  ('maid-visa', '2-Year Maid Visa', 'Two-year maid visa with GCC sponsorship.', 'visa', 110);

insert into public.services (category_id, slug, name, short_description, is_popular, sort_order)
select c.id, s.slug, s.name, s.short_description, s.is_popular, s.sort_order
from (values
  ('general-cleaning', 'home-cleaning', 'Home Cleaning', 'Regular cleaning for apartments and villas.', true, 10),
  ('general-cleaning', 'move-in-cleaning', 'Move-In Cleaning', 'Get your new home spotless before you move in.', false, 20),
  ('general-cleaning', 'move-out-cleaning', 'Move-Out Cleaning', 'Leave your old home clean for handover.', false, 30),
  ('deep-cleaning', 'deep-cleaning', 'Deep Cleaning', 'Intensive cleaning of every room, top to bottom.', true, 10),
  ('deep-cleaning', 'furniture-cleaning', 'Furniture Cleaning', 'Sofa, mattress and upholstery cleaning.', false, 20),
  ('hourly-maid', 'hourly-maid', 'Hourly Maid', 'A professional maid for as many hours as you need.', true, 10),
  ('maid-services', 'daily-maid', 'Daily Maid', 'A maid who comes every day.', false, 10),
  ('maid-services', 'weekly-maid', 'Weekly Maid', 'A maid on the days of the week you choose.', false, 20),
  ('maid-services', 'temporary-maid', 'Temporary Maid', 'Short-term help for busy periods.', false, 30),
  ('maid-services', 'regular-housekeeping', 'Regular Housekeeping', 'Ongoing housekeeping on a fixed schedule.', false, 40),
  ('maid-services', 'home-cooking', 'Home Cooking', 'Home-cooked meals prepared in your kitchen.', false, 50),
  ('nanny-baby-care', 'nanny-at-home', 'Nanny at Home', 'Experienced nannies to care for your children.', true, 10),
  ('nanny-baby-care', 'babysitting', 'Babysitting', 'Trusted babysitters for a few hours or an evening.', false, 20),
  ('nanny-baby-care', 'baby-care', 'Baby Care', 'Specialised care for newborns and infants.', false, 30),
  ('elderly-care', 'elderly-care', 'Elderly Care', 'Compassionate support for elderly family members.', false, 10),
  ('home-caregiver', 'home-caregiver', 'Home Caregiver', 'Support with daily living activities at home.', false, 10),
  ('nurse', 'nurse-at-home', 'Nurse at Home', 'Nursing care in the comfort of your home.', false, 10),
  ('home-driver', 'home-driver', 'Home Driver', 'A professional driver for school runs, errands and more.', false, 10),
  ('pet-care', 'pet-care', 'Pet Care', 'Feeding, walking and caring for your pets.', false, 10),
  ('maid-visa', 'two-year-maid-visa', '2-Year Maid Visa (GCC Sponsorship)', 'Two-year maid visa processing with GCC sponsorship.', true, 10)
) as s(category_slug, slug, name, short_description, is_popular, sort_order)
join public.service_categories c on c.slug = s.category_slug;

insert into public.promotions (title, subtitle, image_path, sort_order) values
  ('Find Your Perfect Maid', 'Browse available candidates', 'banners/find-your-perfect-maid.jpg', 10),
  ('Special Recruitment Packages', 'Book your consultation today', 'banners/recruitment-packages.jpg', 20);
