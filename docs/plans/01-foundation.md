---
name: PaperSync Phase 1 - Foundation
overview: 'Move the Flutter project into app/, tighten lint rules, turn the ink models into a pure-Dart domain with stable UUIDs, and add the v1 protocol codec with vectors and a fuzz test. The UI looks and behaves exactly as before.'
todos:
  - id: p1-move
    content: 'Commit the git mv of the Flutter project into app/ (already staged), add root README run steps and a root .gitignore for env/*.json'
    status: pending
  - id: p1-lints
    content: 'Tighten app/analysis_options.yaml (strict-casts, strict-inference, strict-raw-types, extra rules) and fix all findings'
    status: pending
  - id: p1-domain
    content: 'Create lib/domain/ (pure Dart, immutable, value equality, UUID v4 ids, ARGB colors, new sync fields); make lib/models/ink_models.dart re-export it plus a Color extension; update the few UI call sites'
    status: pending
  - id: p1-protocol
    content: 'lib/protocol/: constants (fresh UUIDs), bounds-checked decoder and encoder that never throw, docs/protocol-v1.md'
    status: pending
  - id: p1-tests
    content: 'JSON vectors, codec fuzz test, domain tests, architecture import test; flutter analyze clean, flutter test green, web build unchanged'
    status: pending
isProject: false
---
# Phase 1: Foundation

Goal: set up the structure every later phase depends on. There are no user-visible changes.

## 1. Move into `app/`

- The `git mv` of `lib/`, `test/`, `android/`, `ios/`, `web/`, `pubspec.*`, `analysis_options.yaml`, `.metadata`, and `.gitignore` into [app/](app/) is already staged. Commit it on its own, with no other changes, so Git records pure renames and UI merges from [PR #2](https://github.com/alyastanga/PaperSync/pull/2) still apply.
- Root [README.md](README.md): a short repo layout note and the commands to run (`cd app && flutter pub get && flutter run`).
- Root `.gitignore`: `app/env/*.json` with `!app/env/example.json`. The Phase 4 secrets go there.

## 2. Standards: [app/analysis_options.yaml](app/analysis_options.yaml)

Keep `flutter_lints` and add:

```yaml
analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
linter:
  rules:
    - avoid_dynamic_calls
    - unawaited_futures
    - discarded_futures
    - cancel_subscriptions
    - close_sinks
    - only_throw_errors
    - prefer_final_locals
    - always_declare_return_types
    - test_types_in_equals
```

Fix every finding in the existing UI code. The gate for every phase is `dart format --set-exit-if-changed .` plus `flutter analyze` with zero issues.

## 3. Domain: `app/lib/domain/`

- `ink.dart`, pure Dart with no Flutter imports:
  - `StrokePoint(xMm, yMm, pressure, touching, tMs)`.
  - `Stroke(id, points, colorArgb, width, createdAt, updatedAt, version, deletedAt)`.
  - `NotebookPage(id, notebookId, pageIndex, strokes, createdAt, capturedAt, paperRect, recognizedText)`.
  - `Notebook(id, name, pages, inkColorArgb, createdAt, updatedAt, deletedAt)`.
  - `PaperRect(leftMm, topMm, widthMm, heightMm)`, defaulting to the full 170 x 107 mm.
- Rules:
  - All fields are `final`. Lists are wrapped with `List.unmodifiable`, and value types define `==` and `hashCode`.
  - The constructors check invariants: pressure `0..16383`, coordinates clamped to the page, `version >= 1`, and a non-empty name of at most 200 characters.
- `ids.dart`: `newId()` returns a UUID v4 from the `uuid` package. The current `'$prefix-$seq'` ids repeat after every restart and would collide once data is stored or synced.
- `mutations.dart`: `stroke.edited(...)` returns a copy with `version + 1` and a new `updatedAt`. `stroke.erased()` sets `deletedAt`. The UI hides strokes where `deletedAt != null`.
- [app/lib/models/ink_models.dart](app/lib/models/ink_models.dart) becomes `export '../domain/ink.dart';` plus `extension on Stroke { Color get color => Color(colorArgb); }` and the same for `Notebook`. Screens keep their imports.
- Call sites that build or copy strokes with a `Color` need small changes: [app/lib/data/sample_notebooks.dart](app/lib/data/sample_notebooks.dart), [app/lib/state/app_controller.dart](app/lib/state/app_controller.dart), and the editor. The `EditorTool` and `PageHistory` types stay in `models/` because they are UI state.

## 4. Protocol v1: `app/lib/protocol/`

- `constants.dart`:
  - Freshly generated service and stroke-characteristic UUIDs.
  - Battery Service `0x180F` / `0x2A19`.
  - `headerBytes = 12`, `recordBytes = 8`, `unitsPerMm = 200`, `maxPressure = 16383`, `maxNotificationBytes = 512`.
  - Flag masks: `touching = 0x01`, `hover = 0x02`, `pageMarker = 0x04`; header `replayed = 0x01`.
- `codec.dart`:
  - `DecodeResult decode(Uint8List bytes)` returns a sealed result: `Decoded(Notification)` or `Rejected(reason)`. It never throws.
    - Uses `ByteData` in little-endian order.
    - Rejects packets that are too short, longer than `maxNotificationBytes`, or not version 1.
    - A trailing partial record is dropped and counted in `Decoded.droppedBytes`.
    - Unknown flag bits are ignored. Pressure above 16383 is clamped.
  - `Uint8List encode(Notification)` is used by the simulator and the tests.
  - `Sample` holds `seq = first_seq + index`, `tDeviceMs = base_time_ms + dt_ms`, and `xMm = x / 200`.
- [docs/protocol-v1.md](docs/protocol-v1.md): byte layout tables, UUIDs, units, and seq, boot_id, and time semantics. The firmware work reads this file, and the future `spec.yaml` generator replaces the constants.

## 5. Tests

- `app/test/protocol/vectors/*.json`, each holding `{ "hex": ..., "expect": ... }`. They cover every flag bit, a partial trailing record, `dt` near 255, a replayed header, a page marker, a bad version, and an oversized packet.
- `codec_test.dart`:
  - Checks every vector.
  - `decode(encode(n)) == n` for generated notifications.
  - A fuzz test: 10,000 random byte arrays from 0 to 600 bytes, with a fixed seed, never throw.
- `domain_test.dart`: invariants, equality, and the version bump on edit.
- `architecture_test.dart` reads every `import` in `lib/` and fails on a forbidden edge:
  - `domain` and `protocol` import nothing from Flutter or from other layers.
  - Later phases add their own rules to this test.
- The existing widget tests pass unchanged.

## Done when

- Format, analyze, and tests are clean.
- `flutter build web` succeeds, and the app looks the same as on PR #2.
- The commits are pushed and a draft PR is opened against `cursor/papersync-ui-22e4`.
