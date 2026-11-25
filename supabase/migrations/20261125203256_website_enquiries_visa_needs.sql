-- Website enquiries: two more answers for "What you need" (2-Year Maid Visa pages).
alter table public.website_enquiries drop constraint website_enquiries_need_check;
alter table public.website_enquiries add constraint website_enquiries_need_check
  check (need is null or need in ('housemaid', 'nanny', 'housekeeper', 'cook', 'driver', 'caregiver', 'visa_expat', 'visa_gcc', 'not_sure'));
