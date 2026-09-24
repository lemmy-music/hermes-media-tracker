# Media Tracker

A personal tracker for **movies, series and books** — search a title, add it to your library, and keep track of what you've watched or read.

[![Build & Deploy to GitHub Pages](https://github.com/lemmy-music/hermes-media-tracker/actions/workflows/build-web.yml/badge.svg)](https://github.com/lemmy-music/hermes-media-tracker/actions/workflows/build-web.yml)

**Live app:** https://lemmy-music.github.io/hermes-media-tracker/

> The web app is the development/test surface. The long-term target is a native Android build from the same codebase.

---

## Features

**Search & add** — search movies and series via [TMDB](https://www.themoviedb.org/) and books via [OpenLibrary](https://openlibrary.org/); covers, descriptions and metadata are pre-filled. Duplicate detection keeps the same title out of your library twice.

**Track by media type, at the right granularity:**

| Type | Tracking |
|------|----------|
| **Movie** | status (planned / in progress / completed / dropped) + progress in percent |
| **Book** | status + page-based progress (`page 120 of 400`), editable total page count, percent fallback |
| **Series** | per-**episode** check-off with season browser, bulk "mark season" / "reset season" |

Series status and progress are **derived** from the checked episodes (e.g. 10/19 → 52.6 % and "in progress"; all watched → "completed"). `dropped` is never overwritten automatically.

**Timestamps** — start and completion dates are tracked automatically and can be edited or back-dated manually.

**Language** — German / English toggle (German is the default). Switching updates the UI, TMDB metadata and search language, and re-fetches stored metadata — including episode titles and descriptions.

**Backup** — export the whole library (items, episodes, watch state) as versioned JSON, and import it back in *merge* or *overwrite* mode.

**Per-user data** — magic-link (email) sign-in; every row is scoped to its owner through Postgres Row Level Security, so nothing is readable or writable without an authenticated session. Multiple people can use the same deployment, each with a completely separate library.

---

## Tech stack

| Layer | Choice |
|---|---|
| App | Flutter (Dart 3), Material 3, `provider` for state |
| Backend | Supabase — Postgres, Auth (magic link), Row Level Security |
| Metadata | TMDB (movies/series), OpenLibrary (books) |
| Hosting | GitHub Pages, deployed by GitHub Actions on every push |

---

## Architecture

### Data model

Two tables in Supabase (see [`supabase/migrations/0001_init.sql`](supabase/migrations/0001_init.sql)):

- **`media_items`** — one row per tracked title. Holds the metadata snapshot (title, year, overview, poster, external id) *and* the tracking state (status, progress, timestamps). Books additionally use `authors`, `total_pages`, `isbn`; series use `total_seasons`, `total_episodes`.
- **`episodes`** — per-episode watch state for series (`season_number`, `episode_number`, `watched`, `watched_at`) plus lazily cached TMDB metadata (name, overview, air date, still, runtime). Unique per `(media_item_id, season_number, episode_number)`; deleted with their parent via `ON DELETE CASCADE`.

Both tables have RLS enabled with owner-only policies (`auth.uid() = user_id`); the `anon` role has no table privileges at all.

### Layout

```
lib/
├── config/        app configuration (Supabase project, TMDB token)
├── l10n/          German/English string maps
├── models/        MediaItem, Episode, TMDB + OpenLibrary result models
├── providers/     auth, settings, library (incl. derived series rules)
├── repositories/  Supabase CRUD
├── screens/       library, search, media detail, login, stats
├── services/      TMDB client, OpenLibrary client, export/import, download helper
└── widgets/       shared UI (settings sheet, media tiles, auth gate)
```

---

## Local development

Requires the Flutter SDK.

```bash
git clone https://github.com/lemmy-music/hermes-media-tracker.git
cd hermes-media-tracker
flutter pub get
flutter run -d chrome --dart-define=TMDB_TOKEN=<your TMDB read access token>
```

- The **Supabase project URL and publishable key** are compiled-in defaults in `lib/config/app_config.dart`. They are public by design (they ship in every web bundle; RLS is what protects the data), so no setup is needed to run the app.
- The **TMDB token** is *not* committed. It is injected at build time via `--dart-define=TMDB_TOKEN=…` (GitHub Actions uses the `TMDB_TOKEN` repository secret). Without it the app degrades gracefully: search shows a configuration hint instead of results.

### Checks

```bash
dart analyze     # must be clean
flutter test     # full suite
```

---

## Deployment

Pushing to `main` triggers [`.github/workflows/build-web.yml`](.github/workflows/build-web.yml):

1. install Flutter (stable) and dependencies
2. `dart analyze`
3. `flutter build web --release --dart-define=TMDB_TOKEN=${{ secrets.TMDB_TOKEN }}`
4. publish `build/web` to the `gh-pages` branch, which GitHub Pages serves

---

## Roadmap

| Phase | Scope | State |
|---|---|---|
| 0 | Project setup, Pages pipeline, app shell | ✅ |
| 1a | Supabase schema, magic-link auth, data layer, library list | ✅ |
| 1b | JSON export / import | ✅ |
| 2 | TMDB + OpenLibrary clients, search & detail UI, language toggle | ✅ |
| 3a | Tracking UI for movies and books | ✅ |
| 3b | Series tracking on episode level | ✅ |
| 5 | Polish: filters/sorting, stats screen | ⏳ |
| 6 | Bonus: ISBN barcode scanner | ⏳ |

Detailed vision, decisions and known limitations: [`PROJECT.md`](PROJECT.md).

---

## Data sources

- This product uses the **TMDB API** but is not endorsed or certified by TMDB.
- Book metadata from **[OpenLibrary](https://openlibrary.org/)**.

---

## Notes

- **Book titles are not localized.** OpenLibrary exposes titles at *work* level (usually the original title); localized titles only exist on individual editions. Deferred by choice.
- **Specials (season 0) are not tracked** — they would skew the derived progress. Could be added later behind a toggle.
- Secrets are never committed; API tokens are injected at build time.
