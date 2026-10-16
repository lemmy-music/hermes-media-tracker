# iwatched

A personal tracker for **movies, series and books** — search a title, add it to your library, and keep track of what you've watched or read.

> The app is called **iwatched**. The repository (`hermes-media-tracker`) and the Dart package (`media_tracker`) keep their historical names — the GitHub Pages path is tied to the repo name and the package name is baked into every import.

[![Build & Deploy to GitHub Pages](https://github.com/lemmy-music/hermes-media-tracker/actions/workflows/build-web.yml/badge.svg)](https://github.com/lemmy-music/hermes-media-tracker/actions/workflows/build-web.yml)

**Live app:** https://lemmy-music.github.io/hermes-media-tracker/

> The web app is the current deployment and test surface. The code is kept portable towards a native Android build from the same codebase.

---

## Features

**Search & add** — search movies and series via [TMDB](https://www.themoviedb.org/) and books via [OpenLibrary](https://openlibrary.org/); covers, descriptions and metadata are pre-filled. Duplicate detection keeps the same title out of your library twice. An **ISBN** (ISBN-10 or ISBN-13, check digit validated) can be typed straight into the search field — including dashes, spaces and an `ISBN` prefix. Each result already shows its **library status**: an **"In library"** badge when you track the title and a **"Watched"** badge when it is completed (both, if it is), so you can see at a glance what you already have before tapping.

**Instant feedback** — a freshly added title shows up **immediately**, with no extra server request: it is placed straight into the in-memory library, so the list, the category-tile counts and the search "In library" badge all update the moment the add succeeds instead of waiting for the next reload. The confirmation snack bar then offers an **Open** action that jumps straight into the new entry's detail view — handy to record *where you are* — for example a series opens on the season you're currently watching. It is offered, never forced.

**Track by media type, at the right granularity:**

| Type | Tracking |
|------|----------|
| **Movie** | status (planned / in progress / completed / dropped) + progress in percent |
| **Book** | status + page-based progress (`page 120 of 400`), editable total page count, percent fallback |
| **Series** | per-**episode** check-off with season browser, bulk "mark season" / "reset season" |

Series status and progress are **derived** from the checked episodes (e.g. 10/19 → 52.6 % and "in progress"; all watched → "completed"). `dropped` is never overwritten automatically. Episode titles and descriptions are available inline (tap a row to expand).

**Timestamps** — start and completion dates are tracked automatically and can be edited or back-dated manually.

**Browse by category** — the library tab opens on four fixed category banners (**Movies / Series / Books / All**) with the entry count of each, so a large library does not bury the list on open. Each banner is a tall card (~1 column on phones, 2 from 600 px) whose background is that category's newest cover — with one or two older covers fanned behind it and a dark→transparent scrim keeping the white label/count readable; a category without any cover falls back to a calm theme gradient, never an empty card. Tapping a banner opens the list filtered to that category (the filter chip shows the preselection and stays changeable).

**Find things again** — the library is searchable (title, plus authors for books; diacritic-tolerant, so "herr" finds "Der Herr der Ringe") and filterable by media type and status, with sorting by recently added, title, release year or progress.

**Statistics** —
- *Overview:* counts per type, status distribution, completion rate per type.
- *Over time* (1 / 6 / 12 months / all time): completions per period (movies and books by completion date, series by each watched episode), **watch time** in hours (episode + movie runtimes) and **pages read**.
- Pages come from an actual **reading log** (see below), not an estimate.

**Backup** — export the whole library (items, episodes, watch state) as versioned JSON, and import it back in *merge* or *overwrite* mode.

**Language** — German / English toggle (German is the default). Switching updates the UI, TMDB metadata and search language, and re-fetches stored metadata — including episode titles and descriptions.

**Per-user data** — email sign-in (a **magic link**, a **pasted magic link**, *or* the **one-time code** from the same email); every row is scoped to its owner through Postgres Row Level Security, so nothing is readable or writable without an authenticated session. Multiple people can use the same deployment, each with a completely separate library. Besides tapping the link, the second login step accepts a **pasted link** — or the numeric code — because **iOS isolates storage between Safari and a homescreen-PWA**, so a link opened in another context never lands in the PWA the app is used in. Pasting the link (or typing the code) redeems the token **in the app's own context**. Pasting works even on the Supabase free tier, where the mail template cannot be changed to include the code.

---

## Tech stack

| Layer | Choice |
|---|---|
| App | Flutter (Dart 3), Material 3, `provider` for state, `fl_chart` for charts |
| Backend | Supabase — Postgres, Auth (magic link + pasted link / email code), Row Level Security |
| Metadata | TMDB (movies/series), OpenLibrary (books) |
| Hosting | GitHub Pages, deployed by GitHub Actions on every push |

---

## Architecture

### Data model

Three tables in Supabase (see [`supabase/migrations/`](supabase/migrations)):

- **`media_items`** — one row per tracked title. Holds the metadata snapshot (title, year, overview, poster, external id, runtime) *and* the tracking state (status, progress, timestamps). Books additionally use `authors`, `total_pages`, `isbn`; series use `total_seasons`, `total_episodes`.
- **`episodes`** — per-episode watch state for series (`season_number`, `episode_number`, `watched`, `watched_at`) plus lazily cached TMDB metadata (name, overview, air date, still, runtime). Unique per `(media_item_id, season_number, episode_number)`; deleted with their parent via `ON DELETE CASCADE`.
- **`reading_log`** — signed page deltas per book (`pages`, `logged_at`). Every commit of a book's page position writes one entry (a correction downwards logs a negative value), which is what makes "pages read per period" exact. The migration backfills already-completed books so past periods stay accurate.

All three tables have RLS enabled with owner-only policies (`auth.uid() = user_id`); the `anon` role has no table privileges at all.

### Layout

```
lib/
├── config/        app configuration (Supabase project, TMDB token)
├── l10n/          German/English string maps
├── models/        MediaItem, Episode, ReadingLogEntry, TMDB + OpenLibrary models
├── providers/     auth, settings, library; pure rules (tracking, series, theme)
├── repositories/  Supabase CRUD
├── screens/       library, search, media detail, login, stats
├── services/      TMDB + OpenLibrary clients, ISBN parsing, library filter,
│                  stats calculator, export/import, download helper
└── widgets/       shared UI (library list view + category banners, settings sheet,
                   media tiles, detail sheets, auth gate)
```

Business rules are deliberately kept out of the widgets: page-progress deltas, series
derivation, library filtering and stats aggregation are all **pure functions** with
their own unit tests.

---

## Local development

Requires the Flutter SDK.

```bash
git clone https://github.com/lemmy-music/hermes-media-tracker.git
cd hermes-media-tracker
flutter pub get
flutter run -d chrome --dart-define=TMDB_TOKEN=YOUR_TMDB_TOKEN
```

- The **Supabase project URL and publishable key** are compiled-in defaults in `lib/config/app_config.dart`. They are public by design (they ship in every web bundle; RLS is what protects the data), so no setup is needed to run the app.
- The **TMDB token** is *not* committed. It is injected at build time through a `dart-define` (GitHub Actions passes the `TMDB_TOKEN` repository secret). Without it the app degrades gracefully: search shows a configuration hint instead of results.

### Database

Apply the migrations in [`supabase/migrations/`](supabase/migrations) in order via the Supabase SQL Editor. See [`supabase/README.md`](supabase/README.md) for the auth and URL configuration.

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
3. `flutter build web --release`, injecting the `TMDB_TOKEN` repository secret as a `dart-define`
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
| 5a | Stats screen (overview, completions, watch time, pages) | ✅ |
| 5b | Library search, filters, sorting | ✅ |
| 5c | Reading log (exact pages per period) | ✅ |
| 6a | ISBN text search | ✅ |
| 6b | ISBN barcode scanner (camera) | ⏸️ deferred to a native build |
| 7 | Bulk catch-up prompts, add-as-watched from search | ✅ |
| 8 | Library / watched status badges in search results | ✅ |
| 9 | Category tiles landing screen for the library | ✅ |
| 10 | Season pre-selection when opening a series | ✅ |
| 11 | Instant library adoption of new items + open-from-search | ✅ |
| 12 | Premium category banners with cover artwork | ✅ |
| 13 | Email-code sign-in next to the magic link (iOS PWA fix) | ✅ |
| 14 | Sign in by **pasting the magic link** (the real iOS-PWA fix) | ✅ |

Detailed vision, decisions and known limitations: [`PROJECT.md`](PROJECT.md).

---

## Data sources

- This product uses the **TMDB API** but is not endorsed or certified by TMDB.
- Book metadata from **[OpenLibrary](https://openlibrary.org/)**.

---

## Known limitations

- **Book titles are not localized.** OpenLibrary exposes titles at *work* level (usually the original title); localized titles only exist on individual editions. A localized title would need an extra edition lookup per book.
- **Specials (season 0) are not tracked** — they would skew the derived progress. Could be added later behind a toggle.
- **An ISBN lookup stores the *work* key while showing *edition* metadata** (ISBNs identify a specific printing). This is what lets an ISBN add dedup against a normal title search; the trade-off is that two editions of the same work count as one entry.
- **Reading history** starts from the reading-log migration: the backfill covers already-completed books, but pages read in a book that was in progress at that moment were never recorded.
- **The ISBN barcode scanner is deferred** — `mobile_scanner` is a camera plugin that cannot run in the Flutter-web test loop; the web app ships the text-input path instead.
- **The email-code path needs a Supabase mail-template change.** Supabase only includes the 6-digit code in the sign-in mail when the project's template contains `{{ .Token }}`, and **editing the mail template is not available on the free tier**. On this deployment only the **link** is therefore usable — tap it, or (on a homescreen-PWA) **copy and paste it** into the app (Phase 14). The code field stays in place so the path works unchanged if the project is ever upgraded.
- **A magic-link token is single-use.** The pasted link must be the *unopened* link straight from the mail; once a link (or its token) has been redeemed, a fresh mail is required.

Secrets are never committed; API tokens are injected at build time.
