-- The agency no longer offers temporary home services (hourly, daily,
-- weekly, cleaning, care visits). Only recruitment stays, as on the website.
-- Nothing is deleted: the categories and services are switched off so past
-- records keep their names, and they can be switched back on.

update public.services s
set is_active = false
from public.service_categories c
where c.id = s.category_id
  and c.slug <> 'maid-visa'
  and s.is_active;

update public.service_categories
set is_active = false
where slug <> 'maid-visa'
  and is_active;

-- Offers now always open the hire page (all maids), so they no longer
-- point at a category or service.
update public.promotions
set target_type = 'none',
    target_value = null
where target_type <> 'none';
