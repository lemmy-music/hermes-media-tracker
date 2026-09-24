# Media Tracker — Project Brief

Personal tracker for **movies, series and books**. Mark what you've seen/read and keep optional progress.

## Product Vision (from Daniel, 2026-08-21)

Track three media types with different granularity:

| Type | Core | Extended |
|------|------|----------|
| **Movie** | "watched" status | progress with timestamp and/or percent |
| **Series** | per-**episode** "watched" (default: check off a whole episode) | progress percent / timestamp |
| **Book** | "read" status | percent or page-based progress |

### Metadata
- **Movies & Series:** TMDB (posters, descriptions, seasons, episodes). API key required.
- **Books:** OpenLibrary API **or** Google Books API (decision open — OpenLibrary needs no key).

### Persistence
- **Supabase** (Postgres) stores all status/progress data.
- **JSON export/import** for backup and portability.

### Bonus (last, optional)
- ISBN **text entry** is live (Phase 6a). ISBN **barcode scanning** via `mobile_scanner` (camera) is deferred (Phase 6b) to a future native/Android build — the plugin needs a platform camera and cannot run in the Flutter-web test loop.

## Platform
- **Flutter Web app**, deployed to **GitHub Pages** (debug/test loop).
- UI language: **German / English toggle** in settings (German is the default). The toggle also switches TMDB metadata and search language; OpenLibrary is not localized (see known limitations).

## Repo
- `https://github.com/lemmy-music/hermes-media-tracker` (public, `main`)
- Local clone: `/root/media-tracker`

---

## Roadmap

- [x] **Phase 0 — Setup:** Flutter web project skeleton, GitHub Actions → Pages pipeline, app shell (navigation), theme.
- [x] **Phase 1a — Data layer:** Supabase project + schema (media items, status/progress, episodes), magic-link auth, models + repository, client wiring, library list (loading / empty / error / list).
- [x] **Phase 1b — Data layer:** versioned JSON export/import of the whole library (settings sheet: export downloads `media_tracker_export_<date>.json`, import offers **merge** (skips already-tracked `external_source`/`external_id`) or **overwrite** (deletes all first); fresh ids + `user_id` from the DB, episodes re-linked to their parent, watch state preserved; conditional web download helper keeps the code mobile-ready).
- [x] **Phase 2 — Metadata:** TMDB client (search + details + seasons/episodes) ✓, **OpenLibrary book client** (search + details + ISBN lookup) ✓, search & detail UI (movies/series/books) ✓, DE/EN language toggle ✓, language-driven metadata refresh ✓ (episodes too, since Phase 3b).
- [x] **Phase 3a — Tracking UI (movies & books):** status (planned / in progress / completed / dropped), progress percent for movies, page-based progress for books (percent fallback), editable started/completed timestamps, delete with confirmation. Series entries showed a "phase 3b" notice instead of tracking controls (replaced by Phase 3b).
- [x] **Phase 3b — Series tracking (episodes):** season/episode browser in the series detail view (lazy-loaded from TMDB on first open, localized), per-episode check-off, bulk "mark season" / "reset season" (with confirmation). The series status and progress are **derived** from the checked episodes (10/19 → 52.6 % and "in progress"; all → "completed"; `dropped` is never overwritten; `started_at`/`completed_at` fill gaps) and persisted on `media_items`, so the library list and stats keep reading the same columns. The manual status selector is hidden for series. The language switch also re-fetches the stored episode metadata (watch state preserved).
- [x] **Phase 5a — Stats:** analytics screen (`lib/screens/stats_screen.dart`). **Overview** (always visible): counts per type (movies/series/books), a status-distribution donut with legend, completion rate per type, localized empty state. **Time-based** (switch: 1 / 6 / 12 months / all time, default 12): stacked completions over time (movies/books by `completed_at`, series by each watched episode's `watched_at`; monthly buckets, yearly for an all-time span > 24 months; empty months stay as gaps), watch time (episode + movie runtimes, missing runtimes skipped) and pages (from the **reading log**, see Phase 5c). All aggregation is pure and unit-tested in `lib/services/stats_calculator.dart`; charts use `fl_chart`. `media_items.runtime` (migration `0002`) is written on add and by the metadata refresh.
- [x] **Phase 5c — Reading log:** exact "pages read per period" instead of the old approximation. Migration `0003_reading_log.sql` adds `public.reading_log` (`id`, `user_id` → `auth.users`, `media_item_id` → `media_items` `on delete cascade`, signed `pages`, `logged_at`, `created_at`) with owner-only RLS. Every commit of a **book's** page position writes one entry: the signed delta to the previous `progress_current` — the single funnel is `LibraryProvider._applyTracking` + `readingLogDelta` (`lib/providers/tracking_rules.dart`), fed by the page input, the sliders' `onChangeEnd` (a drag release, never each intermediate step), `completed` (logs the remaining pages) and the `planned` reset (logs the whole reduction as a negative entry). Movies/series and books without `total_pages` never log (no page position). A failing log insert is swallowed — it can never break the progress update (and the app keeps working before the migration is applied). `computePagesRead` (`lib/services/stats_calculator.dart`) sums the signed `pages` over the half-open `[start, end)` window, so corrections subtract and a period can legitimately be negative; the stats screen loads the log next to items + episodes. **History is preserved:** the migration's backfill gives every already-completed book a single entry with its full page count dated at `completed_at` (only when it has no entry yet), so past periods do not regress against the old approximation.
- [x] **Phase 5b — Library search, filters & sorting:** the library can be searched, filtered and sorted **client-side on the already-loaded list** (no server round-trip, no DB query, no pagination). A toggled search field filters live over the **title** of every kind and additionally over a **book's authors**; the match is case-insensitive and diacritic-tolerant (`normalizeSearchText` folds umlauts/accents/ß, so "herr" finds "Der Herr der Ringe" and "muller" finds "Müller"). Two horizontally scrollable chip rows filter by **media type** (all/movies/series/books) and **status** (all/planned/in progress/completed/dropped); search and both filters combine with a logical **AND**. Sorting offers **recently added** (`created_at` desc, default), **title A–Z** (case-insensitive, leading articles kept), **release year** (desc) and **progress** (desc) — all stable for equal keys, with missing fields sorted last. A localized result counter ("12 Treffer von 48" / "12 results of 48", singular-aware) appears while a search/filter is active, next to a quick "reset filters" action, and the library gets its own **"no matches"** empty state (clearly distinct from the "library is empty" one). All logic is pure and unit-tested in `lib/services/library_filter.dart`; the screen's search/filter/sort state is **session-only** (never persisted) and the provider's list is never modified.
- [x] **Phase 6a — ISBN text search:** the search field also accepts an **ISBN** (typed, no camera). A pure `parseIsbn` (`lib/services/isbn.dart`) normalizes the input (strips separators plus an `ISBN` / `ISBN-10:` / `ISBN-13:` prefix, upper-cases a trailing `X`) and validates the **check digit** of ISBN-10 and ISBN-13 — a deliberate guard so ordinary 10-/13-digit numbers are *not* mistaken for an ISBN and keep going through the normal text search. On the `Books` and `All` scopes a valid ISBN runs an OpenLibrary **ISBN lookup** instead of the title query (the `Movies` / `Series` scopes keep their normal TMDB search), signalled by a small "ISBN-Suche / ISBN lookup" label; the hit renders like any other book (cover, title, authors, year) with the usual detail sheet + "Add to library" (duplicate handling included), and a miss shows a localized "no book for this ISBN" state that names the ISBN. Because `/isbn/<isbn>.json` resolves to an **edition** (`/books/OL…M`), `OpenLibraryClient.lookupByIsbn` reads the edition's linked **work** (`works[0].key`) and stores the work key as `external_id` — so an ISBN add still dedups against a later title search; author names (absent on the edition payload) come from one best-effort `q=isbn:…` search call. All new strings are localized (DE/EN).
- [ ] **Phase 6b — Bonus, deferred to a native/Android build:** ISBN barcode scanner (`mobile_scanner`). `mobile_scanner` is a platform camera plugin that does not run in the Flutter-**web** debug/test loop (no camera, nothing to exercise in `flutter test`), so it is out of scope for this web deployment. The web app deliberately ships the text-input path (Phase 6a) only.

## Known limitations / backlog

- **Book titles are not localized.** OpenLibrary exposes titles at *work* level, which is usually the original title ("The Lord of the Rings", not "Der Herr der Ringe"); German titles only exist on the individual *editions*. A localized book title would need an extra editions lookup per book. *Deliberately deferred to the very end — current behaviour is acceptable.*
- **Specials (season 0) are not tracked.** The episode loader fetches only the numbered seasons (`season_number >= 1`); the specials season is skipped so it does not skew the derived progress (it is often a large, incomplete extras bucket). This is a pragmatic call for Phase 3b — specials can be added later behind their own toggle.
- **ISBN lookup stores the *work* key while showing *edition* metadata.** `/isbn/<isbn>.json` returns an edition (`/books/OL…M`), but the app tracks books per work, so an ISBN hit is resolved to the edition's linked work (`works[0].key`) and stored with that work key as `external_id` (title/cover/pages/year come from the edition payload, author names from a best-effort `q=isbn:…` search call). Upside: an ISBN add dedups against a normal title search. Trade-off: two different editions (different ISBNs) of the same work count as one entry, and edition-specific metadata (publisher, that exact printing) is not modelled.

## Decisions

1. **Supabase + auth model** → project `vqpkejsxfvaovhdomllw`; **magic-link (email) auth** with owner-only RLS. Chosen over an unauthenticated setup so a leaked publishable key cannot be used to read or write anyone's data.
2. **Metadata sources** → **TMDB** for movies/series (read access token, injected at build time via `TMDB_TOKEN`), **OpenLibrary** for books (no key, no auth). German search results are ranked first on a German UI instead of filtering, and books are excluded from the language-driven metadata refresh (works are not localized). Google Books was considered and dropped.
3. **Deployment** → GitHub Pages via GitHub Actions on every push to `main`; the web app is the debug/test surface, Android is the eventual target.
4. **Rules as pure functions** → page-progress deltas, series derivation, library filtering and stats aggregation live outside the widgets and are unit-tested. Business logic never sits inside a `build()`.
5. **Reading history** → a dedicated `reading_log` table rather than deriving pages from completion dates, so "pages read per period" is exact (see Phase 5c).

