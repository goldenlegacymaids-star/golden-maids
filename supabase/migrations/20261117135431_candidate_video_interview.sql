-- =============================================================================
-- Golden Maids – Video interview per maid (YouTube)
-- =============================================================================
-- Staff paste a YouTube link on the staff website; only the 11-character
-- video ID is stored, so no other kind of link can be saved. The app plays it
-- on the maid's profile (signed-in customers only, like the profile itself).
-- Guests only learn whether a maid has a video (has_video), for the
-- "Video" label on maid cards; the video ID itself is not readable by them.
-- Videos should be uploaded to YouTube as Unlisted, with embedding allowed.

alter table public.candidates
  add column video_id text check (video_id is null or video_id ~ '^[A-Za-z0-9_-]{11}$'),
  add column has_video boolean generated always as (video_id is not null) stored;

comment on column public.candidates.video_id is
  'YouTube video ID of the maid''s interview (Unlisted video, embedding allowed); null = none.';

grant select (has_video) on public.candidates to anon;
