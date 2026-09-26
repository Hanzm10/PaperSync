---
name: PaperSync Phase 3 - Persistence
overview: 'Store notebooks on the phone with encrypted hive_ce boxes behind repositories: atomic per-record writes carrying their own sync flag, live-stroke checkpoints with crash recovery, versioned schema migrations, and safe handling of corrupted files.'
todos:
  - id: p3-schema
    content: 'lib/storage/: fixed typeIds and field indexes in one registry, meta box with schemaVersion, and a migration runner that runs before providers read'
    status: pending
  - id: p3-crypto
    content: 'AES-256 box encryption with a Random.secure key in flutter_secure_storage (Keychain / Keystore); web is demo-only and unencrypted; Android allowBackup off'
    status: pending
  - id: p3-repos
    content: 'NotebookRepository and StrokeRepository with watch streams, per-record syncState flag, soft deletes, and save on stroke close'
    status: pending
  - id: p3-recovery
    content: 'Open-stroke checkpoint every 500 ms and on app pause, recovery on launch, and corrupted-box quarantine with a user-visible notice'
    status: pending
  - id: p3-wire-tests
    content: 'AppModel.notebooks fed from repositories, debug-only seeding; tests for restart survival, crash recovery, migration, corruption, and encryption'
    status: pending
isProject: false
---
# Phase 3: Persistence

Goal: nothing written with the pen, or edited in the app, is lost after a restart, crash, or a phone that's been lost. Storage stays offline-first. Sync in Phase 4 reads from the same records.

## 1. Schema: `app/lib/storage/`

Imports only `domain`.

- `adapters.dart` defines every `TypeAdapter` by hand, with the typeIds and field indexes in one table:
  - `notebook = 1`, `page = 2`, `stroke = 3`, `point = 4`, `checkpoint = 5`.
  - An id or index is never reused or renumbered. A test pins the table.
- Stroke points are stored as a packed `Uint8List` of 12 bytes per point: `x` and `y` as float32, `pressure` as uint16, `flags` as uint16, and `tMs` as uint32 relative to the stroke's start. This keeps boxes small.
- Boxes: `notebooks`, `pages`, and `strokes` (keyed by UUID), `checkpoint` (one key), and `meta` (`schemaVersion`, `installId`).
- `migrations.dart` holds an ordered list of `(fromVersion, run)` steps.
  - `StorageBootstrap.open()` opens `meta`, runs any pending steps in order, and only then opens the data boxes.
  - The app's `main()` awaits this before `runApp`, behind a small splash.

## 2. Encryption and platform

- A 32-byte key comes from `Random.secure()` on first launch and is stored with `flutter_secure_storage` (iOS Keychain, Android Keystore-backed). Every box is opened with `HiveAesCipher(key)`.
- If the key is missing but the boxes exist (for example after a keychain reset), the old files are quarantined as described in section 4. They are never opened with a new key.
- Web is demo-only. Boxes there are unencrypted, and the README says so.
- Android: `android:allowBackup="false"` and `android:fullBackupContent="false"`, so encrypted boxes aren't restored without their key.

## 3. Repositories

- `NotebookRepository` and `StrokeRepository` are interfaces with Hive implementations.
  - Methods: `watchNotebooks()`, `watchPage(id)`, `upsertStroke`, `softDeleteStroke`, `createNotebook`, `renameNotebook`, `addPage`, `softDeletePage`.
- Every record carries `syncState` (`pending` or `synced`) and `ownerId` (null until Phase 4 claims it), written in the same `put`.
  - A single Hive `put` is atomic, so a record can never be written without also being marked for sync. No separate outbox can drift out of step with the data.
- A delete is a tombstone (`deletedAt`) marked `pending`. The Phase 4 sync removes synced tombstones after 30 days.
- Write policy:
  - A stroke is saved on `StrokeClosed`.
  - Editor changes (move, recolor, erase) are saved when the gesture ends, not on every frame.
  - A move saves once, with one version bump.
- Reads go through `watch` streams built on `box.watch()`, with debouncing. `AppController` stops holding the source of truth and becomes a projection of the repositories plus UI-only state (history, hover, live ids).

## 4. Crash safety

- Checkpoint: while `Drawing`, the open stroke is written to `checkpoint` every 500 ms. It is also written, followed by `box.flush()`, on `AppLifecycleState.paused`, `hidden`, and `detached`.
- Close order: write the stroke, then delete the checkpoint. If the app dies between the two, recovery finds a duplicate id and keeps the stroke that's already stored.
- On launch, a leftover checkpoint becomes a closed stroke on its page, marked `pending`.
- Corruption: `hive_ce` crash recovery is left on, so a torn last frame is truncated. If a box still fails to open:
  - Its file is renamed to `<box>.corrupt-<timestamp>` and a fresh box is opened.
  - The user sees "Some notes couldn't be opened. A copy was kept." The file is never deleted silently, and the app never crashes on start.
- The undo history stays in memory only, which is acceptable and documented.

## 5. Wiring and seeding

- `AppModel.notebooks` comes from `watchNotebooks()` joined with the pages. The public controller API stays the same.
- `sampleNotebooks()` is seeded only when `kDebugMode` is on and `meta` has no `seeded` flag, so release builds start empty.
- Only `ownerId == null` or the current user's rows are shown. This prepares for Phase 4 accounts.

## 6. Tests

These use Hive in a temp directory and a fake secure storage.

- Restart: write strokes, close the boxes, reopen, and get equal data.
- Crash: leave a checkpoint behind, reopen, and the stroke is recovered exactly once.
- Migration: a v1 fixture box upgrades to the current version.
- Corruption: garbage bytes in a box file lead to quarantine plus a notice, with no exception.
- Encryption: the raw box bytes don't contain a known notebook name.
- The typeId and field-index table is pinned.
- `architecture_test.dart` adds the rule that `storage` may import only `domain`.

## Done when

- Analyze, format, and tests are clean.
- On the web demo, a stroke drawn by the simulator is still there after a reload.
- Release-mode startup shows an empty library.
