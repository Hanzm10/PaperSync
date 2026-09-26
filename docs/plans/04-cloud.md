---
name: PaperSync Phase 4 - Cloud
overview: 'Back up and sync notebooks through Supabase: a locked-down schema (forced RLS, check constraints, server-owned timestamps and versions), email OTP sign-in with the session in secure storage, and an idempotent, deterministic sync of pending records.'
todos:
  - id: p4-project
    content: 'Create or select the Supabase project, add SUPABASE_URL and SUPABASE_ANON_KEY as Cloud Agent secrets and app/env/dev.json (gitignored), commit env/example.json'
    status: pending
  - id: p4-schema
    content: 'supabase/migrations/0001_init.sql: tables, forced RLS for authenticated only, check constraints, server triggers for updated_at and monotonic version, indexes; security advisors clean'
    status: pending
  - id: p4-auth
    content: 'Email OTP sign-in sheet from the Device screen, session in flutter_secure_storage, sign-out behavior, account-switch rules'
    status: pending
  - id: p4-sync
    content: 'lib/sync/: SyncService pushes pending records in batches, pulls by server updated_at cursor, deterministic merge, backoff, tombstone purge, syncStatusProvider'
    status: pending
  - id: p4-tests
    content: 'Merge-rule tests, fake-remote sync tests, RLS tests against a local Supabase (two users), end-to-end check on the project'
    status: pending
isProject: false
---
# Phase 4: Cloud

Goal: signed-in users get their notebooks backed up and synced across phones. Signed-out users lose nothing, because Phase 3 already keeps everything on the phone.

## 1. Project and secrets

- Create or pick a Supabase project (free tier). Confirm before any step that has a cost.
- The app only ever holds the project URL and the anon key, which RLS makes safe to ship. The `service_role` key never appears in the app, the repo, or the logs.
- Config:
  - `flutter run --dart-define-from-file=env/dev.json`.
  - `app/env/dev.json` is gitignored. `app/env/example.json` is committed with placeholders.
  - The same two values are added as Cloud Agent secrets for testing.
  - Without them, sync is off and the app behaves as in Phase 3.

## 2. Schema: `supabase/migrations/0001_init.sql`

- Tables. Every table also has `user_id uuid not null default auth.uid() references auth.users on delete cascade`, `created_at`, `updated_at`, and `deleted_at`.
  - `notebooks`: `id uuid pk`, `name text check (char_length(name) between 1 and 200)`, `ink_color bigint`.
  - `pages`: `id`, `notebook_id` referencing `notebooks`, `page_index int check (>= 1)`, `captured_at`, `paper_rect jsonb`.
  - `strokes`: `id`, `page_id` referencing `pages`, `points bytea` (the Phase 3 packed format, with `check (octet_length(points) <= 240000)`, i.e. 20,000 points), `color bigint`, `width real check (> 0 and < 50)`, `version int check (>= 1)`.
  - `page_text`: `page_id pk`, `text`, `tsv tsvector generated`. The table is created now, and search fills it later.
- Security:
  - `alter table ... enable row level security; alter table ... force row level security;` on every table.
  - `revoke all on all tables in schema public from anon;`
  - Per table, four policies (select, insert, update, delete) `to authenticated`, each with `using ((select auth.uid()) = user_id)` and, for insert and update, `with check ((select auth.uid()) = user_id)`.
  - Child tables also check that the parent row belongs to the same user, for example that a stroke's `page_id` points to the user's own page. This blocks cross-user attachment.
  - No `security definer` functions and no public views.
- Server-owned fields, set by a `before insert or update` trigger:
  - `updated_at = now()` using the server clock, so the pull cursor can't be skewed by a phone's clock.
  - An update with `new.version < old.version` raises an error, so an older edit can never overwrite a newer one.
  - `user_id` can't change on update.
- Indexes: `(user_id, updated_at)` on each table, plus `page_id` and `notebook_id` foreign-key indexes.
- Verification: run the Supabase security and performance advisors after applying, and resolve every finding.

## 3. Auth

- Email OTP uses `signInWithOtp(email)` followed by `verifyOTP(type: email, token)`. There is no magic link, so no deep links or redirect URLs to secure.
  - Supabase's built-in OTP rate limits and expiry stay on.
  - The sheet validates the email format and allows a resend after 60 s.
- The session is stored in `flutter_secure_storage` through a custom `LocalStorage` passed to `Supabase.initialize(authOptions: ...)`, not in plain shared preferences.
- The sign-in sheet opens from the Device screen, built with the existing widgets.
- Signing out stops sync and clears the session. Local notebooks stay on the phone.
- Account rules:
  - On first sign-in, rows with `ownerId == null` are claimed by that user.
  - Rows owned by another account are never uploaded, and are hidden while signed in as someone else.
- Logs never contain tokens, emails, or OTP codes.

## 4. Sync: `app/lib/sync/`

Imports only `domain` and `storage` interfaces.

- `SyncService` runs when signed in, on connectivity regained, on app resume, and 5 s after the last local write. At most one run happens at a time.
  - **Push:** in parent-first order (notebooks, then pages, then strokes), upsert `pending` records in batches of 200. Each record is marked `synced` only if its local `version` hasn't changed since it was read. Otherwise it stays `pending` for the next run.
  - **Pull:** fetch `updated_at > cursor` per table, ordered by `updated_at`, in pages of 500. The cursor is stored in `meta` only after a page is written locally.
- Client-generated UUID primary keys make every push idempotent. A retry after a timeout can't create duplicates.
- Merge (a pure function, fully tested):
  - A higher `version` wins.
  - At an equal version, the later server `updated_at` wins.
  - A tombstone at an equal or higher version wins.
  - A local `pending` record is never overwritten by a lower-version remote row.
- Errors are sealed: `Offline`, `AuthExpired` (refresh once, then ask to sign in again), `Rejected(row)` (a constraint or RLS error; that row is quarantined, not retried forever), and `ServerError` (backoff 5 s, doubling to 5 min, with jitter).
- Synced tombstones older than 30 days are purged locally.
- `syncStatusProvider` is `idle`, `syncing`, or `failed(reason)`. The UI shows only "Couldn't back up · saved on this phone."

## 5. Tests

- Merge rules: table tests for every version, timestamp, and tombstone combination.
- Sync against a fake remote:
  - Idempotent retry.
  - An edit made during a push stays `pending`.
  - Push order.
  - The cursor only advances after a local write.
  - A rejected row is quarantined.
  - Backoff.
- RLS against a local Supabase from the Supabase CLI, if Docker is available (otherwise against the project):
  - User A can't select, update, or delete user B's rows.
  - User A can't attach a stroke to user B's page.
  - Anon can do nothing.
  - An older version is rejected.
- End to end: sign in, draw with the simulator, check the rows in Supabase, delete the local data, sign in again, and get the notebooks back.
- `architecture_test.dart` adds the rule that `sync` never imports `ble`, `capture`, or UI.

## Done when

- Analyze, format, and tests are clean, and the advisors report no findings.
- A notebook drawn on one install appears on a second install signed into the same account.
- A different account sees none of it.
