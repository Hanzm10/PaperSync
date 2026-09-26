# Decisions recorded in Phase 1

These differ from the earlier module plan on purpose. Later phases follow
them.

## Sync flag on the record

Each notebook, page, and stroke carries a `syncState` of `pending` or
`synced`. A single save writes the record and that flag together. There is
no separate upload queue that can get ahead of, or behind, the ink.

Deletes stay on the record as `deletedAt` until they have been synced. The
UI hides a stroke whose `deletedAt` is set.

## Stroke points on the server

Stroke points will be stored as packed bytes, 12 bytes per point, rather
than a JSON array of `{x, y, p, t}`. The packed form is about four times
smaller, and the server can check the length. Phase 1 keeps points in memory
as `StrokePoint` values. The column change lands with the cloud schema work.

## Sign-in

Sign-in is an emailed 6-digit code (Supabase email OTP). A magic link would
need a deep link into the app; the code does not. The anon key is the only
Supabase credential that ships with the app. The service role key does not.
