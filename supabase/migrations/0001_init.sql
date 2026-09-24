-- Media Tracker — initial schema
-- Run once in the Supabase SQL Editor (Dashboard → SQL Editor → New query → paste → Run).
--
-- Design notes:
--   * Single-user data ownership: every row carries user_id and RLS restricts
--     all access to the owning user (no user bleed, nothing shared).
--   * The `anon` role gets NO table privileges — authentication is required.
--   * `media_items` holds both the metadata snapshot and the tracking state
--     (1:1, so no extra join is needed).
--   * `episodes` caches TMDB episode metadata and holds the per-episode
--     watched state; user_id is denormalized so RLS policies stay simple.

-- ─────────────────────────────────────────────────────────────────────────────
-- Tables
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.media_items (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,

  -- classification
  kind             text not null check (kind in ('movie', 'series', 'book')),

  -- metadata snapshot
  title            text not null,
  original_title   text,
  release_year     int,
  overview         text,
  poster_url       text,
  external_source  text check (external_source in ('tmdb', 'openlibrary')),
  external_id      text,

  -- book-specific
  authors          text[],
  total_pages      int,
  isbn             text,

  -- series-specific
  total_seasons    int,
  total_episodes   int,

  -- tracking state
  status           text not null default 'planned'
                     check (status in ('planned', 'in_progress', 'completed', 'dropped')),
  progress_percent numeric(5, 2) check (progress_percent between 0 and 100),
  progress_current int,                 -- page (book) or episode number (series)
  started_at       timestamptz,
  completed_at     timestamptz,

  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table if not exists public.episodes (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  media_item_id  uuid not null references public.media_items (id) on delete cascade,

  season_number   int not null,
  episode_number  int not null,

  -- cached TMDB metadata
  name        text,
  overview    text,
  air_date    date,
  still_url   text,
  runtime     int,

  -- watch state
  watched     boolean not null default false,
  watched_at  timestamptz,

  created_at  timestamptz not null default now(),

  unique (media_item_id, season_number, episode_number)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Indexes
-- ─────────────────────────────────────────────────────────────────────────────

create index if not exists media_items_user_id_idx      on public.media_items (user_id);
create index if not exists media_items_kind_idx         on public.media_items (user_id, kind);
create index if not exists episodes_media_item_id_idx   on public.episodes (media_item_id);
create index if not exists episodes_user_id_idx         on public.episodes (user_id);

-- Prevent duplicate library entries for the same external item, but allow
-- multiple manual (external_id is null) entries.
create unique index if not exists media_items_external_uniq
  on public.media_items (user_id, external_source, external_id)
  where external_id is not null;

-- ─────────────────────────────────────────────────────────────────────────────
-- updated_at maintenance
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists media_items_set_updated_at on public.media_items;
create trigger media_items_set_updated_at
  before update on public.media_items
  for each row execute function public.set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- Row Level Security — owner-only access, authenticated users only
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.media_items enable row level security;
alter table public.episodes    enable row level security;

drop policy if exists "media_items_owner_all" on public.media_items;
create policy "media_items_owner_all"
  on public.media_items
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "episodes_owner_all" on public.episodes;
create policy "episodes_owner_all"
  on public.episodes
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- Privileges — authenticated only; the `anon` role gets nothing.
-- ─────────────────────────────────────────────────────────────────────────────

grant select, insert, update, delete on public.media_items to authenticated;
grant select, insert, update, delete on public.episodes    to authenticated;
