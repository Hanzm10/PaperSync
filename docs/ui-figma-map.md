# PaperSync Figma map

Source: [PaperSync, node 2003:129](https://www.figma.com/design/9Q4PKHBzk3oVIigtd75nLo/PaperSync?node-id=2003-129).

Read with `FIGMA_TOKEN` (`file_content:read`) from the environment, header `X-Figma-Token` only. `GET /v1/me` and `GET /v1/files/:key/styles` return 403 for this scope. The node tree (`GET /v1/files/9Q4PKHBzk3oVIigtd75nLo/nodes?ids=2003:129`) and image renders succeeded. Raw JSON and PNG renders stay in gitignored `design/figma-cache/`. The file is one light canvas, `PaperSync Mobile` (`2003:171`), 13 frames at 390×844. There is no dark-mode frame. Dark colors are the inverse palette already paired with these light values, in `app/lib/theme/tokens.dart`.

`#8A847C` meta text is about 3.3:1 on the canvas, under WCAG AA. Screens use `#726D66`, the same hue at 4.5:1. The original value is `PaperTokens.lightFigmaMeta`.

| Frame | Node | App surface | Status |
| --- | --- | --- | --- |
| Welcome | `2003:172` | Launch gate: Sign in, Create account, Continue without account | Decision. Not built. |
| Sign in | `2003:174` | Email and password form | Decision. Not built. |
| Create account | `2003:176` | Name, email, password | Decision. Not built. |
| Reset password | `2003:178` | Email a reset link | Decision. Not built. |
| Library | `2003:180` | `LibraryScreen` | Built |
| Notebook | `2003:182` | `NotebookPagesScreen` | Built |
| Live capture | `2003:184` | `LiveCaptureScreen` | Built. Ink keeps the 170×107 mm canvas. |
| Page editor | `2003:186` | `PageEditorScreen` | Built |
| Pen | `2003:188` | `DeviceScreen` when a pen is bonded | Built |
| Settings | `2003:190` | Account, pen, sync, recognition, appearance, export | Decision. Not built. |
| Account and sync | `2003:192` | Profile, mobile data, storage, sign out | Decision. Not built. |
| Pen setup | `2003:194` | `DeviceScreen` while pairing | Built. Bluetooth permission stays in front of Connect. |
| Sync recovery | `2003:196` | `SyncIssueScreen` | Built for the failure itself. The per-page waiting list is a decision. |

## Decisions

These frames need behavior Phases 1–4 do not have. They are not wired up as silent extras.

- **Welcome, Sign in, Create account, Reset password.** Phase 4 sign-in is email OTP. `SignedInAccount` stores an id, not a password, and reset links were rejected in favor of a code. The sheet on the pen screen (`showSignInSheet`) is that flow, restyled with the same fields, buttons, and type. "Continue without account" is already how the app opens: `LibraryScreen` is home.
- **Settings.** Handwriting recognition is the out-of-scope ML Kit search. Appearance, export defaults, and a settings destination are new preferences with nowhere to live in `AppController`.
- **Account and sync.** The design shows a display name, email, storage used, and a mobile-data switch. The auth type deliberately omits email so it is not logged, and nothing records storage or that switch.
- **Sync recovery page list.** `SyncFailed` is a reason, not a list of unsynced pages. The screen shows the real backup failure, retry (`syncNow`), and "Continue offline". It does not invent "3 pages" or "Pages 4, 5, and 6".
- **Search.** The plan names Search. The Figma file has no search frame. `SearchScreen` stays, using the same tokens. Results still match saved `recognizedText`. Handwriting search that needs ML Kit is not added.
- **Loading.** No loading frame. Storage opens before the first frame, so the library does not show a spinner.
- **Empty, error, couldn't back up.** Empty library, the quarantine notice, and the backup-failed banner are states on `LibraryScreen`. The banner opens `SyncIssueScreen`.

## What was built

Shared chrome follows the auto-layout: 60 dp bars, text actions (Search, Back, Close, More), status pill, notebook cards, page rows, editor clusters, primary buttons, dialogs, and the sign-in sheet. Hit targets are at least 48 dp, so some controls are taller than the 46 dp Figma buttons. Widgets take spacing and type from `PaperTokens` / `PaperType` and color from `AppColors`.

Illustrations exported as SVG and registered in `app/pubspec.yaml`:

- `assets/images/ink-preview.svg` (`2003:199`) on the empty library.
- `assets/images/pen-glyph.svg` (`2007:71`) on pen setup. Chrome colors follow the theme.
- `assets/images/sync-warn.svg` (`2007:88`) on the sync issue screen.

There were no bitmap illustrations, so there are no 1x/2x/3x PNGs. Inter (OFL, `app/assets/fonts/OFL.txt`) replaces `google_fonts`. No Figma URL is left in the app code.

The live sheet in the file is 342×420. Capture still uses the tablet aspect (`pageAspect`) so a page stays the shape the pen writes. Chrome around it (radius 12, hairline, no shadow) follows the file. The file has no effects.
