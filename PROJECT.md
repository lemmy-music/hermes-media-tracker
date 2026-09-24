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
- UI language: **English**.

## Repo
- `https://github.com/lemmy-music/hermes-media-tracker` (public, `main`)
- Local clone: `/root/media-tracker`

---

## Roadmap

- [x] **Phase 0 — Setup:** Flutter web project skeleton, GitHub Actions → Pages pipeline, app shell (navigation), theme.
- [x] **Phase 1a — Data layer:** Supabase project + schema (media items, status/progress, episodes), magic-link auth, models + repository, client wiring, library list (loading / empty / error / list).
- [ ] **Phase 1b — Data layer:** JSON export/import of local state.
- [~] **Phase 2 — Metadata:** TMDB client (search + details + seasons/episodes) ✓, **OpenLibrary book client** (search + details + ISBN lookup) ✓, search & detail UI (movies/series/books) ✓; season/episode browser follows in Phase 4.
- [ ] **Phase 3 — Tracking UI:** library list/grid, add media, status toggles, progress controls with timestamps.
- [ ] **Phase 4 — Series episodes:** season/episode browsing, per-episode check-off, bulk "mark season".
- [ ] **Phase 5 — Polish:** filters/sorting, stats, empty states, offline behaviour.
- [ ] **Phase 6 — Bonus:** ISBN scanner (`mobile_scanner`).

## Open decisions
1. ~~Supabase project credentials + whether to use Supabase Auth (login) or a single-user setup.~~ → Project `vqpkejsxfvaovhdomllw`; **magic-link (email) auth**, RLS is owner-only.
2. TMDB API key.
3. ~~Book metadata source: OpenLibrary vs Google Books.~~ → **OpenLibrary** (no API key, no auth). German results are ranked first on a German UI instead of filtering, and books are excluded from the language-driven metadata refresh (works are not localized).
