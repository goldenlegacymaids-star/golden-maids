-- =============================================================================
-- Golden Maids – Insights: articles for the public website
-- =============================================================================
-- Staff write articles on the staff website; the public website shows the
-- published ones under /en/insights/ and /ar/insights/. English is required;
-- the Arabic version is optional and all-or-nothing (title, summary and text),
-- and the Arabic page exists only once it is filled in.
--
-- "Admin approves content": any staff member can write and edit drafts, but
-- only administrators can publish, unpublish, edit a published article or
-- delete one. Every change is written to the admin audit log.

create table public.website_articles (
  id            uuid primary key default gen_random_uuid(),
  slug          text not null unique
                  check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) between 3 and 90),
  category      text not null default 'hiring'
                  check (category in ('hiring', 'visas', 'prices', 'care', 'news')),
  title_en      text not null check (char_length(btrim(title_en)) between 5 and 120),
  summary_en    text not null check (char_length(btrim(summary_en)) between 20 and 300),
  body_en       text not null check (char_length(btrim(body_en)) between 50 and 40000),
  title_ar      text check (title_ar is null or char_length(btrim(title_ar)) between 5 and 120),
  summary_ar    text check (summary_ar is null or char_length(btrim(summary_ar)) between 20 and 300),
  body_ar       text check (body_ar is null or char_length(btrim(body_ar)) between 50 and 40000),
  cover_path    text check (cover_path is null or char_length(cover_path) between 3 and 300),
  cover_alt_en  text check (cover_alt_en is null or char_length(cover_alt_en) <= 200),
  cover_alt_ar  text check (cover_alt_ar is null or char_length(cover_alt_ar) <= 200),
  status        text not null default 'draft' check (status in ('draft', 'published')),
  published_at  timestamptz,
  author_id     uuid default auth.uid() references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint website_articles_arabic_complete check (
    (title_ar is null) = (summary_ar is null) and (title_ar is null) = (body_ar is null)
  ),
  constraint website_articles_published_date check (status = 'draft' or published_at is not null)
);

comment on table public.website_articles is
  'Insights articles for the public website. Staff write drafts; administrators publish. Arabic is optional (all three Arabic fields or none).';
comment on column public.website_articles.body_en is
  'Article text: paragraphs separated by a blank line, "## " for headings, "- " for list items.';

create index website_articles_published_idx on public.website_articles (status, published_at desc);
create index website_articles_author_id_idx on public.website_articles (author_id);

-- The publish date is set when an article is first published, and the author
-- never changes after the article is created.
create or replace function private.website_articles_prepare()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.author_id := (select auth.uid());
  else
    new.author_id := old.author_id;
  end if;
  if new.status = 'published' and new.published_at is null then
    new.published_at := now();
  end if;
  return new;
end;
$$;

revoke all on function private.website_articles_prepare() from public, anon, authenticated;

create trigger website_articles_prepare
  before insert or update on public.website_articles
  for each row execute function private.website_articles_prepare();

create trigger website_articles_set_updated_at
  before update on public.website_articles
  for each row execute function private.set_updated_at();

create trigger website_articles_audit
  after insert or update or delete on public.website_articles
  for each row execute function private.log_admin_change();

-- -----------------------------------------------------------------------------
-- Row Level Security
-- -----------------------------------------------------------------------------
alter table public.website_articles enable row level security;

revoke all on public.website_articles from anon, authenticated;
-- Guests see everything about a published article except who wrote it.
grant select (id, slug, category, title_en, summary_en, body_en, title_ar, summary_ar, body_ar,
              cover_path, cover_alt_en, cover_alt_ar, status, published_at, created_at, updated_at)
  on public.website_articles to anon;
grant select, insert, update, delete on public.website_articles to authenticated;

create policy "Guests read published articles"
  on public.website_articles for select to anon
  using (status = 'published' and published_at <= now());

create policy "Users read published articles; staff read all"
  on public.website_articles for select to authenticated
  using ((status = 'published' and published_at <= now()) or (select private.is_staff()));

create policy "Staff write drafts; admins publish"
  on public.website_articles for insert to authenticated
  with check (
    (select private.is_admin())
    or ((select private.is_staff()) and status = 'draft')
  );

create policy "Staff edit drafts; admins edit all"
  on public.website_articles for update to authenticated
  using (
    (select private.is_admin())
    or ((select private.is_staff()) and status = 'draft')
  )
  with check (
    (select private.is_admin())
    or ((select private.is_staff()) and status = 'draft')
  );

create policy "Admins delete articles"
  on public.website_articles for delete to authenticated
  using ((select private.is_admin()));

-- -----------------------------------------------------------------------------
-- Cover pictures (public: they appear on the website). Pictures only – never
-- documents. Staff upload; administrators replace or delete.
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('insight-images', 'insight-images', true, 5242880,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- (Anyone can view the pictures through their public address; this lets staff
-- list them, which replacing and deleting also need.)
create policy "Staff list insight images"
  on storage.objects for select to authenticated
  using (bucket_id = 'insight-images' and (select private.is_staff()));
create policy "Staff upload insight images"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'insight-images' and (select private.is_staff()));
create policy "Admins update insight images"
  on storage.objects for update to authenticated
  using (bucket_id = 'insight-images' and (select private.is_admin()))
  with check (bucket_id = 'insight-images' and (select private.is_admin()));
create policy "Admins delete insight images"
  on storage.objects for delete to authenticated
  using (bucket_id = 'insight-images' and (select private.is_admin()));
