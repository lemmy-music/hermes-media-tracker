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
- ISBN barcode scanning via `mobile_scanner` (camera).

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
- [ ] **Phase 1b — Data layer:** JSON export/import of local state.
- [x] **Phase 2 — Metadata:** TMDB client (search + details + seasons/episodes) ✓, **OpenLibrary book client** (search + details + ISBN lookup) ✓, search & detail UI (movies/series/books) ✓, DE/EN language toggle ✓, language-driven metadata refresh ✓ (episodes too, since Phase 3b).
- [x] **Phase 3a — Tracking UI (movies & books):** status (planned / in progress / completed / dropped), progress percent for movies, page-based progress for books (percent fallback), editable started/completed timestamps, delete with confirmation. Series entries showed a "phase 3b" notice instead of tracking controls (replaced by Phase 3b).
- [x] **Phase 3b — Series tracking (episodes):** season/episode browser in the series detail view (lazy-loaded from TMDB on first open, localized), per-episode check-off, bulk "mark season" / "reset season" (with confirmation). The series status and progress are **derived** from the checked episodes (10/19 → 52.6 % and "in progress"; all → "completed"; `dropped` is never overwritten; `started_at`/`completed_at` fill gaps) and persisted on `media_items`, so the library list and stats keep reading the same columns. The manual status selector is hidden for series. The language switch also re-fetches the stored episode metadata (watch state preserved).
- [ ] **Phase 5 — Polish:** filters/sorting, stats, empty states, offline behaviour.
- [ ] **Phase 6 — Bonus:** ISBN scanner (`mobile_scanner`).

## Known limitations / backlog

- **Book titles are not localized.** OpenLibrary exposes titles at *work* level, which is usually the original title ("The Lord of the Rings", not "Der Herr der Ringe"); German titles only exist on the individual *editions*. A localized book title would need an extra editions lookup per book. *Deliberately deferred to the very end — current behaviour is acceptable.*
- **Specials (season 0) are not tracked.** The episode loader fetches only the numbered seasons (`season_number >= 1`); the specials season is skipped so it does not skew the derived progress (it is often a large, incomplete extras bucket). This is a pragmatic call for Phase 3b — specials can be added later behind their own toggle.

## Open decisions
1. ~~Supabase project credentials + whether to use Supabase Auth (login) or a single-user setup.~~ → Project `vqpkejsxfvaovhdomllw`; **magic-link (email) auth**, RLS is owner-only.
2. TMDB API key.
3. ~~Book metadata source: OpenLibrary vs Google Books.~~ → **OpenLibrary** (no API key, no auth). German results are ranked first on a German UI instead of filtering, and books are excluded from the language-driven metadata refresh (works are not localized).
