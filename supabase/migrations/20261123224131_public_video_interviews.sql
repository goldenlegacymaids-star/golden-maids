-- =============================================================================
-- Golden Maids – Video interviews on the public website
-- =============================================================================
-- The public website plays each maid's interview on her profile, so guests
-- may now read the YouTube video ID (agreed by the agency, 24 Nov 2026).
-- Row Level Security is unchanged: guests still only see published,
-- non-archived maids. The video stays Unlisted on YouTube, and only staff can
-- set or change it. Bio, religion, marital status and documents stay hidden.

grant select (video_id) on public.candidates to anon;

comment on column public.candidates.video_id is
  'YouTube video ID of the maid''s interview (Unlisted video, embedding allowed); null = none. Readable by guests: the public website plays it on her profile.';
