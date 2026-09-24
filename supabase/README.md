# Supabase setup

## 1. Run the schema

Dashboard → **SQL Editor** → **New query** → paste the contents of
[`migrations/0001_init.sql`](migrations/0001_init.sql) → **Run**.

Creates:

| Table | Purpose |
|---|---|
| `media_items` | One row per tracked movie / series / book — metadata snapshot **and** tracking state (status, progress, timestamps) |
| `episodes` | Per-episode watch state for series + cached TMDB episode metadata |

Both tables have **RLS enabled** with owner-only policies (`auth.uid() = user_id`),
and the `anon` role has no privileges — so nothing is readable or writable
without an authenticated session.

## 2. Auth

- Provider: **Email (Magic Link)** — Dashboard → Authentication → Providers → Email.
- Dashboard → Authentication → **URL Configuration**:
  - **Site URL:** `https://lemmy-music.github.io/hermes-media-tracker/`
  - **Redirect URLs:** same URL (`http://localhost:*` is useful for local dev)

Magic links are sent by Supabase's built-in mailer, which is rate limited
(a few mails per hour on the free tier). One sign-in per device is normally
enough — the session is persisted and refreshed automatically.

## 3. Client wiring

The Flutter client (`lib/config/app_config.dart`) ships with the project URL
and the **publishable** key as compile-time defaults, so no extra setup is
needed for a normal build. Both are public by design: RLS decides what an
unauthenticated request may see (nothing).

Override for a different project / environment:

```sh
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://xxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_xxx \
  --dart-define=AUTH_REDIRECT_URL=http://localhost:5555/
```

`AUTH_REDIRECT_URL` defaults to the current origin + path, which already covers
GitHub Pages and local dev — but it must still be listed under
**Authentication → URL Configuration → Redirect URLs**, otherwise Supabase
silently falls back to the Site URL.

Never put an `sb_secret_...` / service-role key in the client: it bypasses RLS.
