-- Media Tracker — reading log (pages read over time)
-- Run once in the Supabase SQL Editor (Dashboard → SQL Editor → New query → paste → Run).
--
-- Why: the stats screen could previously only approximate "pages read in a period"
-- by summing the page counts of books *completed* in that period, because no
-- reading history was stored. This table records the actual deltas.
--
-- How entries are created (app side):
--   * whenever page progress on a book is committed (slider released / value
--     submitted), the delta to the previous position is logged
--   * correcting downwards logs a negative delta, so totals stay correct
--   * completing a book via status logs the remaining pages
--
-- `pages` is intentionally signed (int, not a constraint >= 0).

create table if not exists public.reading_log (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  media_item_id uuid not null references public.media_items (id) on delete cascade,
  pages         int not null,
  logged_at     timestamptz not null default now(),
  created_at    timestamptz not null default now()
);

create index if not exists reading_log_user_time_idx
  on public.reading_log (user_id, logged_at desc);
create index if not exists reading_log_item_idx
  on public.reading_log (media_item_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- Row Level Security — owner-only, authenticated only
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.reading_log enable row level security;

drop policy if exists "reading_log_owner_all" on public.reading_log;
create policy "reading_log_owner_all"
  on public.reading_log
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update, delete on public.reading_log to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Backfill
--
-- Books that were already completed have no log entries, and would therefore
-- contribute nothing to past periods (a regression against the old
-- approximation). Give each one a single entry with its full page count,
-- dated at its completion.
-- ─────────────────────────────────────────────────────────────────────────────

insert into public.reading_log (user_id, media_item_id, pages, logged_at)
select m.user_id, m.id, m.total_pages, m.completed_at
from public.media_items m
where m.kind = 'book'
  and m.status = 'completed'
  and m.completed_at is not null
  and m.total_pages is not null
  and m.total_pages > 0
  and not exists (
    select 1 from public.reading_log l where l.media_item_id = m.id
  );
