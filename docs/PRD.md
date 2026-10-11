# PaperSync software PRD

Status: draft 1 for review. Scope: the phone app and its cloud backup. Firmware and the tablet hardware are covered only where the app depends on them.
Target: working demo in early November 2026.

## 1. Summary

PaperSync keeps a digital copy of what you write in a real paper notebook. A graphics tablet sits under the notebook and reads the pen. The phone app receives the strokes live, draws them, saves them as pages in notebooks, makes the handwriting searchable, and backs it up to the cloud.

The app already exists (Flutter, Riverpod, Hive, Supabase) and runs end to end against a simulated pen. This PRD covers four things:

1. A second way to get pen data into the phone: a USB cable to an Android phone (OTG), alongside the default Bluetooth path.
2. Handwriting search that really recognizes ink (ML Kit), not just text typed into a field.
3. A visual refresh toward the attached reference image.
4. The gaps between "works in a demo" and "something a student trusts with their notes".

## 2. Goals, non-goals, success measures

### Goals

- G1. Pen strokes appear on the phone while the user writes, over Bluetooth by default.
- G2. If the ESP32 USB host path cannot be made to work, the product still works on Android over a USB cable, with no change to the rest of the app.
- G3. Nothing the user writes is lost: not on a dropped link, an app kill, a phone restart, or a failed upload.
- G4. Handwritten notes can be found by searching for words in them.
- G5. The app looks like the reference image: soft, bright, rounded, blue accented, with notebook covers and sketch thumbnails.

### Non-goals for this release

- Firmware, tablet hardware, and the ESP32 USB host work. The app defines what it needs from them (section 8) and nothing more.
- Typed text, image insertion, and layers. The product is a faithful copy of paper, so the app does not let you add things that are not on the paper (section 7.3).
- iOS over a cable. iOS has no USB OTG path for this. See risk R1.
- Password reset by email, team sharing, collaborative editing, a web client beyond the existing demo.

### Success measures (demo day)

| Measure | Target |
| --- | --- |
| Pen to screen delay, Bluetooth | 100 ms or less at the 95th percentile |
| Pen to screen delay, USB cable | 50 ms or less at the 95th percentile |
| Strokes lost over a 10 minute writing session with two forced reconnects | 0 |
| Lost strokes after killing the app mid-stroke, then reopening | at most the last 500 ms of one stroke |
| Search finds a handwritten word written on a test page | 8 of 10 words, in either mode |
| Cold start to library on a mid range Android phone | under 2 s |
| `flutter analyze` issues, test suite | 0 issues, all green |

## 3. Users and scenarios

Primary user: a student or professional who prefers writing on paper but wants notes on their phone.

1. Class notes. The user opens the app, taps Capture, writes for 50 minutes, presses the page button on the controller to start a new page, and later searches "Fourier" to find the page.
2. Cable only. The user's controller is not available or Bluetooth is flaky. They plug the tablet into their Android phone, accept one permission prompt, and write.
3. Recovery. The phone dies mid-lecture. After it restarts the notebook is intact up to the last half second.
4. Share. The user exports a page as PDF or image and sends it.

## 4. Current state (what already exists in `app/`)

Verified from the repository, not from running the app.

| Area | State |
| --- | --- |
| Protocol v1 codec, bounds checked, fuzz tested | Built (`lib/protocol`) |
| Capture state machine, page markers, sequence and gap handling | Built (`lib/capture`) |
| Bluetooth transport with scheduler, backoff, pinned device, permissions | Built (`lib/ble`, `lib/platform`) |
| Simulated pen for web and tests | Built |
| Encrypted local storage, checkpoints, migrations, corruption quarantine | Built (`lib/storage`) |
| Email and password sign in, Supabase sync with row level security | Built (`lib/sync`, `supabase/migrations`) |
| Screens from the earlier monochrome Figma | Built (`lib/screens`) |
| Search over text already stored on a page | Built. No handwriting recognition runs. |
| PDF and image export | Built (`lib/export`) |
| USB transport | Not started |
| Ink recognition (ML Kit) | Not started |
| Reference-image visual design | Not started |

Known UI-only placeholders to resolve or hide: password reset, storage size, last sync time, mobile data switch, handwriting recognition toggle, export default (see `docs/ui-figma-map.md`).

## 5. Connection modes

The app has one `PenTransport` interface (bytes, link status, battery). Everything downstream of it (decoder, capture, storage, UI) must not know which mode is active.

| Mode | Platforms | Chain | Status |
| --- | --- | --- | --- |
| **Bluetooth (default)** | Android, iOS | tablet, ESP32-S3 (USB host), BLE, phone | Built on the phone side. Depends on the ESP32 host test. |
| **USB cable (OTG)** | Android only | tablet, USB-C cable, phone | New. Fallback if the ESP32 host path fails, and an option even if it works. |
| **Hybrid** | Android only | tablet to phone by cable for ink, ESP32 to phone by BLE for page button, status LED, battery | New. This is the planned form of the fallback. |
| Simulator | Web, debug builds | none | Built |

### 5.1 Selection rules

- FR-C1 (P0). Bluetooth is the default on first launch on every platform.
- FR-C2 (P0). Settings has a Connection choice: Bluetooth, USB cable. USB cable is shown only on Android.
- FR-C3 (P1). On Android, when a known tablet is plugged in while the setting is Bluetooth, the app asks once: "Use the USB cable for this tablet?" Yes switches the setting. No is remembered per device.
- FR-C4 (P0). Only one mode is active at a time. Switching mid-capture ends the open stroke cleanly, saves it, and starts a new stroke on the new mode.
- FR-C5 (P0). Release builds can never select the simulator (existing rule, keep it).

### 5.2 Decision gate

The hardware side runs a test to decide whether the ESP32 can read the tablet. The software plan does not wait for it.

| Hardware result | Software consequence |
| --- | --- |
| ESP32 reads the tablet and forwards over BLE | Bluetooth is the main path. USB cable ships as an Android option. iOS supported. |
| ESP32 cannot read the tablet | Hybrid becomes the main Android path. iOS has no pen data path and ships as a library viewer only (R1). |

USB transport work starts now, in parallel, so the gate decides what is promoted in the UI, not whether the code exists.

## 6. Functional requirements

Priorities: P0 is needed for the demo, P1 should make it, P2 is later.

### 6.1 Pairing and Bluetooth (existing, harden)

- FR-B1 (P0). Scan lists only devices advertising the PaperSync service (`6f0c2d14-...`). Pair once, pin the device, auto reconnect only to the pinned device.
- FR-B2 (P0). Link states shown to the user: Connected, Reconnecting, Disconnected, plus Saving when buffered data is being replayed. Reconnect uses capped exponential backoff with jitter.
- FR-B3 (P0). Replayed samples (header flag 0x01) are merged without duplicating strokes already drawn live. Matching uses `boot_id` and `seq`.
- FR-B4 (P1). Negotiate the largest MTU the phone offers. Packets stay at most 512 bytes (62 records).
- FR-B5 (P0). Battery comes from the standard Battery Service. If absent, the battery pill is hidden, never faked.
- FR-B6 (P1). Show firmware version only when the device exposes Device Information (0x180A). Otherwise hide the row.

### 6.2 USB cable mode (Android, new)

- FR-U1 (P0). A new `UsbPenTransport` implements `PenTransport`. It emits the same v1 notification bytes the Bluetooth path emits, so the codec, capture and storage code stay unchanged.
- FR-U2 (P0). Device discovery uses Android `UsbManager`. The scan result lists attached USB devices that match the known tablet (vendor and product id from the hardware capture, section 8.2). Other devices are ignored.
- FR-U3 (P0). The app requests USB permission with the system dialog and handles three outcomes: granted, denied, device removed during the prompt. Denial shows a one line explanation and a retry.
- FR-U4 (P0). Declare a `usb-device` filter in the manifest so plugging in the tablet can offer to open PaperSync. Without a match the app does nothing on plug in.
- FR-U5 (P0). After permission: claim the HID interface (force claim, so Android's own HID handling lets go), send SET_IDLE, read interrupt IN reports continuously on a background isolate or native thread, and parse report ID 9 (position, pressure, tilt). Report ID 5 (position only) is ignored while ID 9 is present.
- FR-U6 (P0). Convert each HID report to a v1 record. The transport owns `boot_id` (random per connection), `first_seq` (counts from 0 per connection), and `base_time_ms` (monotonic milliseconds since connect). Pack up to 62 records or 255 ms into one notification, whichever comes first.
- FR-U7 (P0). Pen lifts and hovers map to flags: touching when pressure is above zero and the pen is in contact, hover when in range but not touching. Pen leaving range flushes the batch immediately.
- FR-U8 (P0). Unplugging the cable moves the link to Disconnected within 1 s and ends the open stroke. Plugging in again reconnects without asking permission again when Android already granted it.
- FR-U9 (P0). Mistakes in HID data (short report, wrong report id, values out of range) are dropped and counted, never thrown. Same untrusted-bytes rules as Bluetooth.
- FR-U10 (P1). If the tablet needs more than SET_IDLE to start streaming (SET_PROTOCOL, SET_REPORT), the transport sends them from a small table keyed by vendor and product id.
- FR-U11 (P1). Tilt and azimuth are decoded and carried in the transport layer but not stored until the data model has fields for them (see 8.3).
- FR-U12 (P1). Show a power warning if the tablet browns out the phone port (device resets within 5 s of connect). Suggest a powered adapter.
- Battery for the USB path: the tablet reports none, so the pill shows the controller battery in hybrid mode and is hidden otherwise.

Implementation note: Flutter has no first-party HID over USB plugin. Write a small Kotlin platform channel (`UsbManager`, `UsbDeviceConnection`, `UsbRequest`) behind the Dart interface. Keep the Dart side in `lib/usb`, with layer rules matching `lib/ble` (imports `protocol` only). The platform channel lives in `lib/platform`.

### 6.3 Controller link (hybrid mode)

In hybrid mode the ESP32 is no longer on the ink path. It is a small BLE accessory.

- FR-X1 (P0). The app connects to the controller with the same pairing flow as 6.1 while ink comes from USB.
- FR-X2 (P0). A page marker from the controller (BOOT button) starts a new page. The app inserts a marker at the current time into the capture timeline, the same effect as a record with the page marker flag (0x04) in the existing codec.
- FR-X3 (P0). Decided: the marker is a normal notification on the existing stroke characteristic with a single record, flags `0x04`, x and y zero. It reuses the codec and needs no new characteristic. Firmware sends it the same way in both Bluetooth and hybrid mode.
- FR-X4 (P1). Controller LED status (connected, capturing, low battery) is driven by firmware from its own state. The app does not write to it in this release.
- FR-X5 (P0). If the controller is not connected in hybrid mode, capture still works. A new page then needs an on-screen New page button. Show a quiet "Controller not connected" note, not an error.

### 6.4 Capture

- FR-K1 (P0). Live Capture shows the page being written on a canvas with the tablet's 170 by 107 mm shape, and a pill that reads Live Capture with link state.
- FR-K2 (P0). Strokes render within one frame of arrival. Pressure drives line width.
- FR-K3 (P0). Hover shows a small cursor dot, not ink.
- FR-K4 (P0). A page marker closes the current page and opens the next in the same notebook. An empty page is not created twice in a row.
- FR-K5 (P0). Target notebook for capture is chosen before writing starts (last used by default). Changing it mid-capture applies from the next page.
- FR-K6 (P0). Checkpoint the open stroke every 500 ms and on app pause. Recover exactly once after a crash.
- FR-K7 (P1). Capture needs the app in the foreground. The screen stays awake while Live Capture is open. If the app is backgrounded, the open stroke is saved and the link state shows Paused. No foreground service in this release.
- FR-K8 (P1). Undo last stroke and redo while capturing. Undo only affects the app's copy and never touches paper.
- FR-K9 (P2). Zoom and pan the capture canvas with a minimap.

### 6.5 Library and notebooks

- FR-L1 (P0). Library shows notebooks as covers (name, page count, cover color, menu) and a New notebook tile, and a Recent pages list with a thumbnail, notebook, page number, and time.
- FR-L2 (P0). Create, rename, change cover color, change default ink color, delete (with confirm, soft delete, synced as a tombstone).
- FR-L3 (P0). Page grid for a notebook with real ink thumbnails. Thumbnails must not repaint on unrelated rebuilds (known issue: `PageRow` rebuilds its stroke list every build, so every thumbnail repaints).
- FR-L4 (P0). Grid cell height fits its content. Pages with no recognized text do not reserve space for it (known issue).
- FR-L5 (P1). Star a page, shown as a star on the row and available as a filter in Search.
- FR-L6 (P1). Reorder and delete pages in a notebook, move a page to another notebook.
- FR-L7 (P2). Tags on pages and notebooks. The Tags filter chip in Search appears only when this ships.

### 6.6 Page view and editor

Ink is captured, not drawn. The editor is for viewing and tidying.

- FR-E1 (P0). View a page with pinch zoom, pan, and a "Page 12 of 24" header with swipe or arrows to move between pages.
- FR-E2 (P0). Undo and redo (in memory, as already decided in `docs/decisions.md`).
- FR-E3 (P0). Eraser: tap a stroke to remove it. Removal is a tombstone, so it syncs and can be undone.
- FR-E4 (P1). Lasso select: choose strokes, then delete or recolor them. Copy and paste are P2.
- FR-E5 (P1). Ink display style: color and a width multiplier for a selection or the whole page. This changes rendering only. Raw stroke data is never altered.
- FR-E6 (P1). Paper style per notebook: blank, dotted, lined, grid. Display and export only.
- FR-E7 (P2). Minimap while zoomed.

### 6.7 Search and recognition

- FR-S1 (P0). Search across notebook names, page titles, and recognized text, with filter chips: All, Pages, Notebooks, Text (Tags later, FR-L7).
- FR-S2 (P0). Results grouped as Best match and Text matches. Match words are highlighted in a snippet.
- FR-S3 (P0). Recognition runs on device with ML Kit Digital Ink Recognition. Strokes are fed in capture order, per page, after the page closes and again when its ink changes.
- FR-S4 (P0). Recognition is queued and runs off the UI thread. A page can be marked Not recognized yet. A failure never blocks capture or saving.
- FR-S5 (P0). Language model download is explicit: Settings shows the language, size, and a download button. Recognition is off until a model is present. (ML Kit downloads models on demand.)
- FR-S6 (P1). Recognized text is stored on the page and synced to `page_text` so a second device can search without recomputing.
- FR-S7 (P2). Recognition is English only in this release. Other languages later.
- FR-S8 (P2). Reindex all pages from Settings.

Honest limit: recognition quality depends on the writer, the language model and stroke quality. The success target is 8 of 10 test words, not full transcription.

### 6.8 Export and share

- FR-P1 (P0). Export a page as PDF or PNG. Export a notebook as one PDF. Uses the system share sheet. (Existing, keep.)
- FR-P2 (P1). Export fits the page to the chosen paper style. Page size is the tablet's active area, not A4. Export may scale it to fit a standard sheet.

### 6.9 Account and sync

- FR-A1 (P0). Using the app without an account is a first class path. Data stays on the phone, encrypted.
- FR-A2 (P0). Sign in or create account with email and password. Session in secure storage.
- FR-A3 (P0). Sync is per record, idempotent, and retries with backoff. The sync pill shows Up to date, Syncing, or Couldn't back up, and opens a recovery screen with the real list of affected pages.
- FR-A4 (P0). Wi-Fi only versus mobile data switch is real: it gates `SyncService`, not just a toggle.
- FR-A5 (P1). Show a last synced time stored locally, and an on-phone storage size. Cloud quota is not shown because there is none.
- FR-A6 (P2). Password reset by email. Until then the control is hidden, not a dead button.
- FR-A7 (P0). `service_role` never ships. Only the project URL and anon key are in the app.

### 6.10 Settings

Sections: Pen, Cloud and storage, Recognition, Appearance, About.

- Pen: connection mode, paired device with status and battery, firmware (when known), forget device, controller status in hybrid.
- Cloud and storage: account, sync switch, Wi-Fi only, on-phone size.
- Recognition: on or off, language, model download.
- Appearance: light, dark, system.
- Remove "Auto-lock" and "Paper size A4" from the reference image: neither maps to anything in this product.

## 7. Experience and visual design

### 7.1 Design language (taken from the reference image)

Copy the look. Do not copy the structure or behavior.

- Surfaces: very light cool grey app background, pure white cards, large corner radius (16 to 20 dp on cards, full pill on chips and status), soft diffuse shadows plus a 1 px hairline. No heavy borders.
- Accent: one confident royal blue (about `#3D5AFE`) for primary buttons, the active tab, selected chips, toggles, and the pen-tool highlight. Tinted light blue fill for selected rows.
- Notebook covers: colored cover cards with a subtle texture or gradient (royal blue, near black, cream), name at top left, page count chip at bottom left, three dot menu at bottom right. A New notebook tile sits in the same row with a plus.
- Thumbnails: page previews render the real ink on a warm off-white paper tint, so they look like small sketches.
- Status chips: soft pills. Live Capture in light blue with a waveform glyph. "Syncing in real time" in green text. Battery as a pill with a green battery glyph and percentage. Bluetooth glyph shown in blue when connected.
- Floating chrome: on capture and editor, tools sit in floating white capsules with shadow, over the canvas. They do not take a fixed toolbar strip.
- Typography: Inter (already bundled). Semibold large titles, regular body, small grey meta text (about 12 to 13 sp). Uppercase small section labels in Settings.
- Canvas: faint dot grid on a warm paper tone for capture and editor. Ink is charcoal by default, with the notebook's default color option.
- Icons: rounded line icons, 24 dp, filled when active.
- Motion: short, calm. Cards lift slightly on press. The live pill breathes while the link is active.
- Dark mode: derive from the same tokens. Cards go to elevated dark grey, accent stays blue, covers keep their color.

Accessibility still wins over the reference where they conflict: text contrast at least 4.5 to 1 (the existing `lightMeta` change stands), hit targets at least 48 dp, status never shown by color alone.

This replaces the monochrome token choices recorded in `docs/ui-figma-map.md`. Update `lib/theme/tokens.dart` and `AppColors` to match, and keep the token approach so a screen never hard codes a color.

### 7.2 Navigation

Bottom bar with five items, in a floating rounded bar like the reference:

| Tab | Purpose |
| --- | --- |
| Library | Notebooks and recent pages. Top right cloud button shows sync state and opens sync details. |
| Search | Search and filters. |
| Capture | Prominent center action. Starts or resumes live capture on the last notebook. |
| Pen | Connection mode, pairing, battery, controller status. |
| Profile | Account, sync, recognition, appearance, about. |

The reference image's fifth tab is Sync. Sync is a state, not a place, so it becomes the cloud button and a section in Profile.

### 7.3 What from the reference image to build, change, or drop

| Reference element | Decision | Why |
| --- | --- | --- |
| Library with covers and Recent pages | Build | Core navigation |
| Search with filter chips and Best match | Build | Matches FR-S1 and FR-S2 |
| Live Capture pill, syncing text, battery pill | Build | Real states from the link and sync service |
| Notebook and page header with "Page 12 of 24" | Build | Page navigation |
| Floating vertical tool strip | Change | Tools limited to what makes sense: select, eraser, undo, redo |
| Pen tray (pen types, colors, thickness) | Change | The real pen is paper. App offers ink color and width multiplier as display style only (FR-E5), not pen types |
| Pen, eraser, lasso, text, image tools | Change | Keep eraser and lasso. Drop text and image (not on the paper) |
| Layers panel (Sketch, Shading, Color, Paper background) | Drop | Ink arrives as one timeline from one pen. No layers |
| Paper background row in layers | Change | Becomes Paper style in notebook settings |
| Minimap | Later (P2) | Useful only when zoomed |
| Notebook settings (name, cover color, paper type) | Build | FR-L2, FR-E6 |
| Notebook settings: Page size A4 | Drop | Page is the tablet's active area |
| Settings: device, battery, firmware | Build | Firmware only when known |
| Settings: Cloud sync, storage usage "of 10 GB" | Change | Show sync switch and on-phone size. No cloud quota |
| Settings: Auto-lock | Drop | No meaning here |
| Tags filter | Later (P2) | Needs a tag model |
| Share button on page | Build | Export (6.8) |

## 8. Data, protocol and hardware dependencies

### 8.1 Protocol v1

Unchanged. Positions are 1/200 mm, pressure 0 to 16383, 12 byte header, 8 byte records, 512 byte cap. See `docs/protocol-v1.md`.

### 8.2 Tablet HID (USB cable mode)

Source of truth is the Wireshark capture of the T605 (Lumispark / VINSA). Record the following in a new `docs/hid-t605.md` before USB work is accepted:

- Vendor id and product id.
- Interface number and the interrupt IN endpoint (observed `0x84`).
- Report ID 9 byte map: 10 bytes. Which bytes are status, x, y, pressure (16,384 levels), tilt, azimuth, and their byte order and logical ranges.
- Required setup requests (Windows sent SET_IDLE).

Mapping to v1: scale x and y from the tablet's logical range to 1/200 mm across the 170 by 107 mm active area. Clamp pressure to 16383. Axis orientation and any flip are set per device profile, not hard coded.

### 8.3 Data model changes

- Add optional tilt and azimuth to the in-memory stroke point only after a storage migration is written and tested. Until then they are dropped after the transport. (Stroke points are stored as packed bytes locally and on the server, 16 bytes per point in the code (`app/lib/storage/points.dart`) and in `0001_init.sql`, so adding fields means a versioned migration on both. `docs/decisions.md` and `docs/plans/` still say 12 and should be corrected. The 10 byte figure is the tablet's Report ID 9, a different thing.)
- Add `recognizedText` language and status (`none`, `pending`, `done`, `failed`) to pages. Migration required.
- Add per-notebook `paperStyle`. Migration required.
- Add `starred` on pages. Migration required.

### 8.4 What the app needs from hardware and firmware

| Need | From | Detail |
| --- | --- | --- |
| Tablet vendor id, product id, report 9 map | Hardware | Section 8.2 |
| BLE service and stroke characteristic per v1 | Firmware | When ESP32 reads the tablet |
| Page marker as a flagged record (or a new characteristic) | Firmware | FR-X3 |
| Battery Service | Firmware | Standard 0x180F |
| ESP32 host result (works or not) | Hardware | Decision gate 5.2 |
| In hybrid mode: BLE controller with button and battery only | Firmware | Smaller scope than the full forwarder |

## 9. Non-functional requirements

- **Latency.** Targets in section 2. The decode and draw path must run without allocating per sample in the hot loop.
- **Throughput.** Handle a sustained 200 samples per second per pen without dropping, in either mode.
- **Reliability.** No data loss on link drop, app kill, phone restart, or sync failure. Writes are single Hive puts with the sync flag on the record. Corrupted storage is quarantined, never deleted.
- **Battery.** Capture for 60 minutes costs the phone at most 10 percent over Bluetooth on a reference phone. Measure and record the USB number, which will be higher because the phone powers the tablet.
- **Security.** All bytes from BLE and USB are untrusted. Local data AES-256, key in Keychain or Keystore, Android backup off. Row level security forced on every table. No tokens or emails in logs. Debug tools only in debug builds.
- **Privacy.** Recognition is on device. Nothing leaves the phone without sign in.
- **Accessibility.** Dynamic type up to 200 percent, screen reader labels on every control, contrast per 7.1.
- **Platforms.** Demo devices: a Samsung Android phone for Bluetooth and USB, and an iPhone for Bluetooth only. Android 8.0 and up (OTG needs Android 3.1 host support, practically all current phones). iOS 15 and up for Bluetooth. Confirm the phone supports USB host before offering USB mode.
- **Quality bar** (from the existing plan, still applies): strict lints, sealed classes, no `dynamic`, layer rules enforced by `test/architecture_test.dart`, `pubspec.lock` committed, dependency vulnerability scan before each merge.

## 10. Architecture changes

```
tablet --BLE via ESP32--> BlePenTransport ----\
tablet --USB cable-----> UsbPenTransport -----+--> PenTransport --> codec --> capture --> store --> UI
ESP32 controller (BLE) -> ControllerLink -----/        (page marker, battery)
```

- New `lib/usb/` (Dart, imports `protocol` only): HID report parser, v1 packetizer, device profile table.
- New `lib/platform/usb_host_android.dart` plus Kotlin channel: enumerate, permission, claim interface, control transfer, interrupt read.
- New `ControllerLink` interface: page marker events, battery, status. Bluetooth transport implements it for the same device in Bluetooth mode, a separate BLE controller class implements it in hybrid.
- `state/transport_choice.dart` and `pen_transport_provider.dart`: choose by mode and platform. Release builds exclude the simulator.
- Update `test/architecture_test.dart` to add `usb` to the layer rules.
- Recognition: new `lib/recognition/` with an interface and an ML Kit implementation in `lib/platform`. A queue service in `state/`.
- Theme refresh: `tokens.dart`, `app_colors.dart`, `chrome.dart`, `notebook_card.dart`, `page_row.dart`, bottom bar widget.

## 11. Plan to demo

About three weeks from 2026-10-11.

| Week | Software | Hardware dependency |
| --- | --- | --- |
| 1 (Oct 12 to 18) | Record HID map and ids. Kotlin USB channel that reads raw reports from the tablet on a real Android phone. HID to v1 packetizer with unit tests from captured bytes. Fix `PageRow` repaint and grid height. Theme tokens and bottom bar. | Host test result. HID capture bytes. |
| 2 (Oct 19 to 25) | USB mode end to end in the app, with hot unplug and reconnect. Controller link and page marker. Connection setting and plug-in prompt. Library, search and capture restyled. ML Kit recognition and model download flow. | Firmware: marker and battery. |
| 3 (Oct 26 to Nov 1) | Editor (eraser, lasso, ink style, paper style). Export fit. Real sync switches. Recovery and soak tests. Latency and battery measurements. Demo script and bug fixing. | Hardware freeze. |
| Buffer | Early November | |

Cut order if time runs out: lasso and ink style, paper style, starred pages and reorder, minimap, then recolor. Never cut: USB mode, page marker, recovery, recognition search.

## 12. Risks

| ID | Risk | Likelihood | Effect | Mitigation |
| --- | --- | --- | --- | --- |
| R1 | ESP32 host fails and the product becomes Android only for pen data. iOS can open the library but not capture. | Medium | High | Be explicit in demo scope. Keep the Bluetooth path ready so iOS works if hardware recovers. |
| R2 | The tablet needs a setup request not yet known | Medium | Medium | Profile table (FR-U10). Capture of Windows traffic already exists. |
| R3 | Android takes the HID interface or drops permission | Medium | Medium | Force claim. Handle revoke. Test on two phones. |
| R4 | Tablet draws more current than a phone port gives | Low to medium | High | Measure early. Document a powered adapter. |
| R5 | ML Kit accuracy on student handwriting is poor | Medium | Medium | Set the target at words, not transcripts. Search by partial match. Show confidence-free results. |
| R6 | BLE throughput at 200 Hz drops samples | Low | Medium | MTU negotiation, batching, replay buffer in firmware, sequence gaps surfaced. |
| R7 | Samsung One UI power management or USB permission behavior differs from stock Android | Medium | Medium | Keep capture in the foreground with the screen awake (FR-K7). Test the USB permission flow on the actual Samsung model early. |
| R8 | Schedule | High | High | Cut order in section 11. |

## 13. Decisions and open questions

Decided:

- Demo devices are a Samsung Android phone and an iPhone (Bluetooth test).
- Page marker is a flagged record on the stroke characteristic (FR-X3).
- No background capture. The screen stays awake during capture (FR-K7).
- Recognition is English only.

Still open:

1. Tablet vendor id, product id, and the exact Report ID 9 byte layout (section 8.2). Needed before USB work can be accepted. The Wireshark capture has them.
2. The Samsung model, so USB host support and permission behavior can be checked.
3. Is cloud-synced search on a second device needed for the demo, or is on-phone recognition enough? (FR-S6 is P1.)
4. Is the app name and logo staying as is, given the visual refresh?

## 14. Acceptance tests

- Bluetooth: pair, write 10 minutes, kill Bluetooth twice, confirm no lost strokes and no duplicates after replay.
- USB: plug in, accept permission, write, unplug mid-stroke, plug in again, confirm the stroke is saved, the link recovers, and no second prompt appears.
- Hybrid: ink over USB, press the controller button three times, confirm three new pages.
- Mode switch mid-capture saves the open stroke and continues.
- Kill the app mid-stroke, reopen, and the ink is recovered once.
- Write 10 known words, search each in airplane mode, at least 8 found.
- Sign in, write offline, go online, confirm sync, sign in on a second device and see the page.
- Light and dark screenshots match the design language checklist in 7.1. Contrast checks pass.
- `flutter analyze` and `flutter test` pass. Architecture test includes `usb`.
