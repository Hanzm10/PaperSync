# PaperSync software PRD

Status: draft 1 for review. Scope: the phone app and its cloud backup. Firmware and the tablet hardware are covered only where the app depends on them.
Target: working demo in early November 2026.
Hardware source of truth: the PaperSync SSOT document shared by Hanz on 2026-10-11, plus the captured packet in `docs/hid-t605.md`. Where it differs from `docs/protocol-v1.md`, section 8.1 says which one wins.

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

The ESP32 host test has failed so far. The tablet, a mouse and a keyboard all stop at `ENUM: CHECK_SHORT_DEV_DESC FAILED`, the first control transfer. Power sequencing, boot timing, pin mapping, the USB mode setting and the esp32beans library are ruled out. The untested causes are Dupont jumper signal quality, a fault on the clone board, and the Arduino core host stack. Until that changes, treat the Android cable path as the main way pen data reaches the phone, with the ESP32 as a BLE controller (hybrid mode). The SSOT says the tablet's six hardware keys did not work over Android OTG, which implies the pen interface was reachable from an Android phone. That is encouraging but not proof until Report ID 9 is read inside the app on a phone.

USB transport work starts now, in parallel, so the gate decides what is promoted in the UI, not whether the code exists.

## 6. Functional requirements

Priorities: P0 is needed for the demo, P1 should make it, P2 is later.

### 6.1 Pairing and Bluetooth (existing, harden)

- FR-B1 (P0). Scan lists only devices advertising the PaperSync service (`6f0c2d14-...`). Pair once, pin the device, auto reconnect only to the pinned device. The UUIDs in `docs/protocol-v1.md` are locked and replace the placeholder UUID in the SSOT.
- FR-B2 (P0). Link states shown to the user: Connected, Reconnecting, Disconnected, plus Saving when buffered data is being replayed. Reconnect uses capped exponential backoff with jitter.
- FR-B3 (P0). Replayed samples (header flag 0x01) are merged without duplicating strokes already drawn live. Matching uses `boot_id` and `seq`.
- FR-B4 (P0). Android requests an MTU of 185 or more right after connecting and before subscribing (`requestMtu`, Android only). iOS negotiates by itself, so the app reads the final MTU and logs it in debug. Firmware sizes each notification to the negotiated MTU minus 3 bytes. At MTU 185 that is 17 records of 10 bytes plus the header, about 20 notifications per second at 330 samples per second. The SSOT's figure of 25 samples per notification assumed smaller records. Packets never exceed 512 bytes.
- FR-B5 (P0). Battery comes from the standard Battery Service. If absent, the battery pill is hidden, never faked.
- FR-B6 (P1). Show firmware version only when the device exposes Device Information (0x180A). Otherwise hide the row.
- FR-B7 (P0). A compact link and battery indicator is visible on every main screen (Library, Capture, Search, page view), not only in Pen settings. "Is my writing being saved right now" must be answerable at a glance.

### 6.2 USB cable mode (Android, new)

- FR-U1 (P0). A new `UsbPenTransport` implements `PenTransport`. It emits the same notification bytes the Bluetooth path emits (section 8.1), so the codec, capture and storage code stay unchanged.
- FR-U2 (P0). Device discovery uses Android `UsbManager`. The scan result lists attached USB devices that match a known tablet by vendor and product id (`0x08F2` and `0x6811` for the Lumispark T605, see `app/lib/usb/tablet_profile.dart`). Other devices are ignored.
- FR-U3 (P0). The app requests USB permission with the system dialog and handles three outcomes: granted, denied, device removed during the prompt. Denial shows a one line explanation and a retry.
- FR-U4 (P0). Declare a `usb-device` filter in the manifest so plugging in the tablet can offer to open PaperSync. Without a match the app does nothing on plug in.
- FR-U5 (P0). After permission: the tablet is a composite device. Claim every HID interface that has an interrupt IN endpoint (`0x84` and `0x86`), never the mass storage interface. Force claim so Android's own HID handling lets go: this also stops Android from moving a mouse pointer with the pen. Read each interface's HID report descriptor, send SET_IDLE, and read all interrupt IN endpoints on one native thread. Which report carries the pen depends on the host: Report ID 9 on `0x84` on Windows, but a phone may get only Report ID 5 on `0x86`. Use Report ID 9 whenever it arrives. Otherwise read any pen report with the layout from its own descriptor and scale it to the whole active area. Use one source at a time so the pen is never drawn twice, and count everything else as dropped.
- FR-U6 (P0). Wrap raw Report ID 9 reports into notification packets. Built: `app/lib/usb/usb_packetizer.dart` emits protocol v1 packets (the format the decoder and capture machine already read), converting X and Y to millimetres with the tablet profile, so nothing downstream changes. v1 has no tilt and no eraser bit, so tilt is dropped and an eraser tip is sent as a hover. The phone owns `boot_id` (random per connection), the sequence number and the clock. A packet is sent at 17 records or 16 ms, whichever comes first, which keeps the pen to screen delay well under 50 ms. When the decoder learns protocol v2 (section 8.1) this switches to v2.
- FR-U7 (P0). Touching comes from the Tip Switch flag (bit 0), hover from In Range (bit 6), never from pressure above zero. The captured hover sample has pressure 29 with the tip up. Mask the flags with `0x47` before reading them: bit 7 is constant padding that the tablet sends as 1. Pen leaving range flushes the batch immediately.
- FR-U8 (P0). Unplugging the cable moves the link to Disconnected within 1 s and ends the open stroke. Plugging in again reconnects without asking permission again when Android already granted it.
- FR-U9 (P0). Mistakes in HID data (short report, wrong report id, values out of range) are dropped and counted, never thrown. Same untrusted-bytes rules as Bluetooth.
- FR-U10 (P1). If the tablet needs more than SET_IDLE to start streaming (SET_PROTOCOL, SET_REPORT), the transport sends them from a small table keyed by vendor and product id.
- FR-U11 (P2). Tilt (X tilt and Y tilt, usages `0x3D` and `0x3E`, signed, no declared unit) is decoded but not stored and no feature depends on it. It read (85, -82) at one corner and (0, 0) at another with the pen held normally, so it is unreliable.
- FR-U12 (P1). Show a power warning if the tablet browns out the phone port (device resets within 5 s of connect). Suggest a powered adapter.
- FR-U13 (P0). Two ways to read the tablet on Android, decided by a spike on a real phone in week 1:
  - Raw (primary): `UsbManager` reads the 10 byte reports directly (FR-U5). Full fidelity: 16384 pressure levels and both tilt axes, nothing reaches the UI, and the tablet area is known exactly.
  - Pointer events (fallback): leave the tablet to Android and read stylus pointer events in Flutter, which give position, pressure from 0 to 1 and one tilt value. Android maps an external tablet onto the whole screen, so the page position would have to be recovered from screen position, and the tablet can also move the system cursor and press buttons in the app. Use it only if the raw path cannot claim the interface.
  - The spike answers three questions: does force claim detach the kernel HID driver, do reports on `0x84` arrive, and what do the pointer events look like if it does not.
- Battery for the USB path: the tablet reports none, so the pill shows the controller battery in hybrid mode and is hidden otherwise.

Implementation note: Flutter has no first-party HID over USB plugin. Write a small Kotlin platform channel (`UsbManager`, `UsbDeviceConnection`, `UsbRequest`) behind the Dart interface. Keep the Dart side in `lib/usb`, with layer rules matching `lib/ble` (imports `protocol` only). The platform channel lives in `lib/platform`.

Status of the cable path (built, not yet run on a phone):

- Dart: `UsbPenTransport` (`app/lib/platform/usb_pen_transport.dart`) implements `PenTransport`. It scans for supported tablets by vendor and product id, asks for USB permission, opens the device, drops reports that are not Report ID 9, reports Connected and Disconnected, and reconnects without a prompt when the same tablet is plugged back in and Android still allows it.
- Kotlin: `UsbHostPlugin.kt` claims only the HID interface on endpoint `0x84` (force claim), sends SET_IDLE, and reads interrupt transfers on a background thread. The manifest declares an optional USB host feature and a USB_DEVICE_ATTACHED filter for the T605, so plugging it in offers to open PaperSync. This is the raw reports route (FR-U13). It has not been compiled or run: there is no Android SDK or phone in the build environment.
- Settings: on Android only, a Connection row switches between Bluetooth (default) and USB cable. The choice is remembered. The pairing screen says "Plug in your tablet" in USB mode.

### 6.3 Controller link (hybrid mode)

In hybrid mode the ESP32 is no longer on the ink path. It is a small BLE accessory.

- FR-X1 (P0). The app connects to the controller with the same pairing flow as 6.1 while ink comes from USB.
- FR-X2 (P0). A page marker from the controller's physical page button starts a new page. The button is wired to a spare ESP32 GPIO (the BOOT button on the dev board until the final button exists). The app closes the current page and opens the next one at that point in the timeline.
- FR-X3 (P0). Wire form: the page button is bit 1 of `header_flags` on a notification (section 8.1). A notification with no records is allowed, so firmware can send it the moment the button is pressed. This replaces the earlier idea of a record flag, because bit 2 of the raw HID flags is Eraser.
- FR-X4 (P1). Controller LED status (connected, capturing, low battery) is driven by firmware from its own state. The app does not write to it in this release.
- FR-X5 (P0). If the controller is not connected in hybrid mode, capture still works. A new page then needs an on-screen New page button. Built: Live Capture has a New page button in its header. Show a quiet "Controller not connected" note, not an error.

### 6.4 Capture

- FR-K1 (P0). Live Capture shows the page being written on a portrait canvas, 107 mm across and 170 mm tall: the 170 by 107 mm tablet turned to portrait, because the notebook it sits under is portrait. The whole tablet area lands exactly on the canvas, so the pen can never write outside it. A pill shows the link state.
- FR-K2 (P0). Strokes render within one frame of arrival. Pressure drives line width.
- FR-K3 (P0). Hover shows a small cursor dot, not ink.
- FR-K4 (P0). A page marker closes the current page and opens the next in the same notebook. An empty page is not created twice in a row.
- FR-K5 (P0). Live page: the user assigns one page of a notebook as the live page (page menu, Set as live page). Pen ink goes to that page, the page shows a Live badge in the notebook, and tapping it opens the live view. Assigning it to the pen is only possible while the pen is connected over Bluetooth. Drawing on the page from the phone has no such limit (FR-K10). There is no separate Live page button. A pen page-button press moves the live page to the next page.
- FR-K6 (P0). Checkpoint the open stroke every 500 ms and on app pause. Recover exactly once after a crash.
- FR-K7 (P1). Capture needs the app in the foreground. The screen stays awake while Live Capture is open. If the app is backgrounded, the open stroke is saved and the link state shows Paused. No foreground service in this release.
- FR-K8 (P1). Undo last stroke and redo while capturing. Undo only affects the app's copy and never touches paper.
- FR-K9 (P2). Zoom and pan the capture canvas with a minimap.
- FR-K10 (P1). Draw on phone is part of the live page, not a separate screen. A page is assigned from its menu: Set as live page (the pen writes into it, needs a connected pen, the default) or Draw on this page (a finger or stylus draws on it, no pen needed). The live view has a Notebook / Draw on phone switch to change the source, with Undo stroke while drawing. The pen is paused while drawing on the phone. Closing the live view ends a page that was assigned for drawing on the phone, so the pen is never left paused by accident. A page assigned to the pen keeps capturing with the pen back in charge. The badge on the page reads Live for the pen and Drawing for the phone.
- FR-K11 (P0). Tablet orientation: Settings has a Tablet orientation row, Turned left (default) or Turned right, which says which way the tablet is turned to make the page portrait. Turned left is the supported setup, with the tablet's three buttons along the bottom: the tablet's top edge is on the left and its top left corner is at the page's bottom left. Turned right puts that corner at the page's top right. It applies to the pen on either connection, and a wrong choice shows up as writing that runs sideways or upside down, so it is one tap to flip. It is remembered.
- FR-K12 (P1). USB check: in USB mode, the Pen screen and Live Capture show a short readout of the cable link (transfers received, pen reports, other report ids, the last transfer in hex, the interfaces the phone sees, which one was claimed). It exists so a problem with the tablet can be read off the screen.

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
- FR-E4 (P1). Lasso select: choose strokes, then delete, recolor, or move them. Copy and paste are P2.
- FR-E5 (P1). Ink display style: color and a width multiplier for a selection or the whole page. This changes rendering only. Raw stroke data is never altered.
- FR-E6 (P1). Paper style per notebook: blank, dotted, lined, grid. Display and export only.
- FR-E7 (P1). Zoom: pages in the editor and the live view zoom with a two finger pinch, a trackpad pinch or Ctrl and the wheel, and Zoom in, Zoom out and Fit page buttons. The wheel and two finger drag pan while zoomed. One finger keeps drawing or moving strokes.
- FR-E8 (P0). Moving a stroke keeps its shape: at the page edge the whole stroke stops, it is never flattened against the edge.
- FR-E9 (P2). Minimap while zoomed.

### 6.7 Search and recognition

- FR-S1 (P0). Search across notebook names, page titles, and recognized text, with filter chips: All, Pages, Notebooks, Text (Tags later, FR-L7).
- FR-S2 (P0). Results grouped as Best match and Text matches. Match words are highlighted in a snippet.
- FR-S3 (P0). Recognition runs on device with ML Kit Digital Ink Recognition. Strokes are fed in capture order, per page, after the page closes and again when its ink changes.
- FR-S4 (P0). Recognition is queued and runs off the UI thread. A page can be marked Not recognized yet. A failure never blocks capture or saving.
- FR-S5 (P0). Language model download is explicit: Settings shows the language, size, and a download button. Recognition is off until a model is present. (ML Kit downloads models on demand.)
- FR-S6 (P2). Recognized text is stored on the page and synced to `page_text` so a second device can search without recomputing. Not needed for the demo: on-phone recognition is enough.
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

### 8.1 BLE wire format

The SSOT (section 3.3) is the source of truth for what the tablet sends. `docs/protocol-v1.md` is what the app implements today. They differ, so this section says what the app will implement.

| Topic | SSOT | App today (v1) | Decision |
| --- | --- | --- | --- |
| Record | 10 byte raw HID Report ID 9, byte 0 is `0x09` | 8 byte record in 1/200 mm, no tilt | 10 byte record with tilt |
| Units | Raw tablet units, app converts to mm | Firmware sends 1/200 mm | Raw units, app calibrates (SSOT wins) |
| Order and replay | None, firmware flushes its buffer on reconnect | Header with `boot_id`, `first_seq`, `base_time_ms`, replay flag | Keep the header (v1 wins) |
| Page marker | "Flag bit 2" | Record flag `0x04` | Header flag, see below. Raw HID bit 2 is Eraser, so neither works as written |
| Service UUID | Placeholder | `6f0c2d14-...` locked | Keep the locked UUIDs |
| Battery | Battery Service `0x180F` | Same | Same |

**Protocol v2 (accepted on the recommendation in the build agent answers, with the conditions below. Hanz can still reverse it before firmware depends on it).**

- Header: 12 bytes, same layout as v1, with `version = 2`. `header_flags` bit 0 is replayed samples, bit 1 is page button pressed.
- Record: 10 bytes, all little endian. Byte 0 is `dt_ms`, an offset from the header's `base_time_ms`. It replaces the Report ID byte, which is always `0x09` and carries no information. Bytes 1 to 9 are identical to HID report bytes 1 to 9: flags, X, Y, pressure, X tilt, Y tilt. The app masks the flags with `0x47`, so the constant bits never matter.
- Page button: a notification with `header_flags` bit 1 set means a new page starts before its first record. It may carry zero records. Firmware sends it immediately on press.
- Size: at MTU 185, 17 records per notification. At the 512 byte cap, 50 records.
- The app decoder accepts versions 1 and 2 during the transition, so the simulator and existing tests keep working.

Why not the SSOT format exactly:

1. Raw HID flags use bit 2 for Eraser, so a page marker on the same bit would be read as an eraser stroke.
2. Notifications are not acknowledged. After a reconnect the firmware cannot know what the phone received, so without a sequence number the app cannot tell lost, duplicated and replayed samples apart.
3. Without timing, a replayed burst loses when the points were written. ML Kit recognizes better with timestamps.

Conditions from the answers: replacing byte 0 costs nothing because the tablet always sends `0x09` there. A single byte cannot dedupe a replay after a long disconnect, which is why the 12 byte header keeps a 32 bit `first_seq`, and `dt_ms` is only an offset inside one notification. The page button is a header flag, so firmware does not need to clear and reuse a constant flag bit. If firmware prefers to put the page button in a spare flag bit instead (bits 3, 4, 5 or 7), it must clear that bit from the tablet's byte first, because the tablet already sets bit 7.

If the firmware owner keeps the SSOT format as written, the app can still decode it (byte 0 is `0x09`), but gap detection and replay dedupe are off, timing is synthesized at about 3 ms per sample, and the page button needs another channel such as a second characteristic.

The captured packet `09 c0 fe 3d 50 5c 1d 00 e3 e5` is a codec test vector for either format.

### 8.2 Tablet HID (USB cable mode and firmware input)

Full detail is in `docs/hid-t605.md`. Settled:

- Vendor id `0x08F2`, product id `0x6811`. The tablet is a composite device: mass storage (ignore), a HID interface on endpoint `0x84` with vendor, mouse and Report ID 9 (preferred), and a HID interface on `0x86` with Report ID 5 (used on the phone when Report ID 9 does not arrive, decoded from its report descriptor).
- Report ID 9 is 10 bytes: report id, flags (bit 0 tip, bit 1 barrel, bit 2 eraser, bit 6 in range, bits 3 to 5 and 7 constant), X u16, Y u16, pressure u16 (0 to 16383), X tilt i8, Y tilt i8.
- Flag bit 7 is constant padding sent as 1. Mask with `0x47`.
- Bytes 8 and 9 are X tilt and Y tilt, not azimuth and altitude. No unit is declared.
- Two decoded captures are unit test vectors (`app/test/usb/hid_report_test.dart`).

Measured corners (X and Y both 0 to 32759):

- Both axes use 0 to 32759 and clamp at the edges. X is about 193 counts per mm.
- The two axes have different scales, because the same raw range covers 170 mm across X and 107 mm down Y.
- (0, 0) is the top left corner, X grows to the right and Y grows downward, so no flip or rotation is needed.
- The values live in `lumisparkT605` in `app/lib/usb/tablet_profile.dart`.

Still pending:

- Whether Android needs the SET_IDLE that Windows sends to each HID interface.

Mapping to millimetres: `xMm = x / 32759 * 170` and `yMm = y / 32759 * 107`, in the tablet's own frame. The app then turns that frame onto the portrait page (FR-K11). Do not use the physical size in the descriptor, which does not match the marketed area.

### 8.3 Data model changes

- Tilt: not stored for now (FR-U11). Tilt is unreliable on this tablet. If it is ever needed, stored points are packed bytes, 16 per point (float32 x, float32 y, uint16 pressure, uint16 flags, uint32 time) in `app/lib/storage/points.dart` and `0001_init.sql`, and two more bytes need a versioned migration on the phone and on the server. The SSOT's schema with `points jsonb` is out of date. Keep packed bytes, which are smaller and size checked.
- Flags: add barrel and eraser to the stored flags if bits are free. Check before changing the layout.
- `docs/decisions.md` and `docs/plans/` still say 12 bytes per point. They should say 16.
- Add recognized text language and status (`none`, `pending`, `done`, `failed`) to pages.
- Add per-notebook `paperStyle` and per-page `starred`.
- Each needs a migration.

### 8.4 What the app needs from hardware and firmware

| Need | From | Detail |
| --- | --- | --- |
| Corner raw values for X and Y | Hardware | Measured: 0 to 32759 on both axes (section 8.2) |
| Firmware reads the Report ID 9 interface (endpoint `0x84`) | Firmware | The tablet also has the Report ID 5 interface |
| Notifications per section 8.1, sized to the negotiated MTU | Firmware | Needs a yes on v2 |
| RAM ring buffer, flushed in order on reconnect with the replay flag set | Firmware | SSOT 3.5. RAM only is enough for the demo |
| Page button on a spare GPIO | Hardware and firmware | Onboard BOOT button (GPIO0, do not hold it during reset) for now. The final button goes on the tablet housing. Status LED is the onboard RGB on GPIO48 |
| Battery Service `0x180F` with a real reading | Hardware and firmware | Battery level is not measurable yet. Add a resistor divider (for example 100k and 100k) from battery plus to an ADC capable GPIO, and map about 3.3 V to 0 percent and 4.2 V to 100 percent. Until then the app hides the battery pill (FR-B5) |
| ESP32 host test result | Hardware | Decision gate in 5.2 |

## 9. Non-functional requirements

- **Latency.** Targets in section 2. The decode and draw path must run without allocating per sample in the hot loop.
- **Throughput.** Handle a sustained 200 samples per second per pen without dropping, in either mode.
- **Reliability.** No data loss on link drop, app kill, phone restart, or sync failure. Writes are single Hive puts with the sync flag on the record. Corrupted storage is quarantined, never deleted.
- **Battery.** Capture for 60 minutes costs the phone at most 10 percent over Bluetooth on a reference phone. Measure and record the USB number, which will be higher because the phone powers the tablet.
- **Security.** All bytes from BLE and USB are untrusted. Local data AES-256, key in Keychain or Keystore, Android backup off. Row level security forced on every table. No tokens or emails in logs. Debug tools only in debug builds.
- **Privacy.** Recognition is on device. Nothing leaves the phone without sign in.
- **Accessibility.** Dynamic type up to 200 percent, screen reader labels on every control, contrast per 7.1.
- **Platforms.** Demo devices: any Android phone with USB host support for Bluetooth and USB (the exact model does not matter), and an iPhone for Bluetooth only. Android 8.0 and up (OTG needs Android 3.1 host support, practically all current phones). iOS 15 and up for Bluetooth. Confirm the phone supports USB host before offering USB mode.
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
| 1 (Oct 12 to 18) | Spike on a real Android phone (FR-U13): force claim the `0x84` interface and read raw reports, and see what pointer events look like as the fallback. HID to v1 packetizer with unit tests from captured bytes. Fix `PageRow` repaint and grid height. Theme tokens and bottom bar. | Any news on the ESP32 host test. |
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
| R7 | Phone vendor power management or USB permission behavior differs from stock Android | Medium | Medium | Keep capture in the foreground with the screen awake (FR-K7). Test the USB permission flow on the demo phone early. |
| R8 | Schedule | High | High | Cut order in section 11. |

## 13. Decisions and open questions

Decided:

- Demo devices are any Android phone with USB host support and an iPhone (Bluetooth test). The Android model does not matter.
- No background capture. The screen stays awake during capture (FR-K7).
- Recognition is English only, on the phone. Syncing recognized text to a second device is not needed for the demo.
- The app name and logo stay as they are.
- The page button goes on the tablet housing. The BOOT button is the stand in until then.
- UUIDs from `docs/protocol-v1.md` are locked.
- Page button is `header_flags` bit 1 (FR-X3).
- Firmware buffer is RAM only for the demo.
- Protocol v2 (section 8.1) is accepted on the recommendation in the build agent answers.
- Vendor id `0x08F2`, product id `0x6811`. Flag bit 7 is constant padding (mask `0x47`). Tilt is X tilt and Y tilt, and it is unreliable.
- Corner values are measured: X and Y both 0 to 32759, different scales per axis, origin at the top left, no flip.

Still open:

1. Whether the ESP32 can ever act as USB host. Until it can, hybrid mode is the main Android path and iOS cannot capture (R1).
2. Raw reports or pointer events for the cable path. The week 1 spike on a real phone decides (FR-U13).
3. Battery level needs a resistor divider on the ESP32 before the Battery Service can report a real value.

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
