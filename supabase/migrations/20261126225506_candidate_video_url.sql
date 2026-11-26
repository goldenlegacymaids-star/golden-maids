-- =============================================================================
-- Golden Maids – Video interviews from any link (not only YouTube)
-- =============================================================================
-- Staff can now give a maid's interview video as any https link: Vimeo,
-- Google Drive, a direct video file (e.g. the agency's own
-- https://gldws.ae/worker/video/612), or another site. YouTube links are still
-- stored as the 11-character video_id (unchanged, so the app keeps working);
-- every other link goes in video_url. A maid has one video: the staff website
-- fills one of the two and clears the other.
-- has_video now means "has either"; it is re-created for that.
-- Guests may read video_url like video_id: the public website plays it on her
-- profile (published, non-archived maids only; Row Level Security unchanged).

alter table public.candidates
  add column video_url text check (
    video_url is null
    or (video_url ~ '^https://[^[:space:]]+$' and length(video_url) <= 500)
  );

comment on column public.candidates.video_url is
  'Interview video as a full https link when it is not on YouTube (Vimeo, Google Drive, a direct video file, other); null = none. Readable by guests: the public website plays it on her profile.';

alter table public.candidates drop column has_video;
alter table public.candidates
  add column has_video boolean generated always as (video_id is not null or video_url is not null) stored;

grant select (has_video, video_url) on public.candidates to anon;
