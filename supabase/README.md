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
