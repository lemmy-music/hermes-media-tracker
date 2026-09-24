-- Media Tracker — add movie runtime
-- Run once in the Supabase SQL Editor (Dashboard → SQL Editor → New query → paste → Run).
--
-- Needed for the stats screen: "TV minutes watched" sums the runtime of watched
-- series episodes (already stored per episode in `episodes.runtime`) plus the
-- runtime of completed movies.
--
-- Existing rows stay NULL until the next metadata refresh (settings → refresh
-- metadata, or automatically on a language switch), which backfills the value
-- from TMDB.

alter table public.media_items
  add column if not exists runtime int;

comment on column public.media_items.runtime is
  'Runtime in minutes. Movies only (series runtime lives on episodes.runtime).';
