# PaperSync firmware

`papersync_relay/` is the ESP32-S3 relay: tablet (USB) to ESP32 (USB host) to
phone (Bluetooth). It forwards the tablet's own reports unchanged, in protocol
v3 (`docs/protocol-v3.md`).

It builds with no warnings on esp32 core 3.0.7 (about 1 MB, 79% of the
default app partition). Verified on the board on 2026-10-18: the tablet's
pen and buttons reach the app over Bluetooth.

## Arduino IDE settings

Keep the setup from the hardware handoff. Do not update the core: on 3.3.12
the USB host never finishes enumeration.

| Setting | Value |
| --- | --- |
| Core | esp32 by Espressif Systems **3.0.7** |
| Board | ESP32S3 Dev Module |
| USB CDC On Boot | Disabled |
| USB Mode | Whichever worked for the raw reader (both build) |
| Upload Mode | UART0 / Hardware CDC |
| Flash Size | 16MB |
| PSRAM | OPI PSRAM |
| Core Debug Level | Info |
| Port | The UART port |

The Serial Monitor runs at 115200 on the UART port.

## Wiring

Unchanged from the handoff: the tablet on the native USB port through the OTG
cable, powered from the MT3608 at 5 V, no hub, nothing on GPIO19 and 20.

## What it does

1. Waits for the tablet, opens it, and claims every HID interface with an
   interrupt IN endpoint (`0x84` and `0x86` on the T605).
2. Reads each interface's HID report descriptor and sends SET_IDLE.
3. Publishes the descriptors on the report descriptor characteristic.
4. Reads every report. Report ID 5 and 9 are pen records: numbered,
   buffered in PSRAM while no phone listens, replayed after a reconnect.
   Anything else (the buttons) goes out at once, only while a phone listens.
5. BOOT (GPIO0) is the page button. The new page starts at the next pen
   record.
6. The RGB LED, when the board has one: blue waiting for the tablet, yellow
   tablet but no phone, green both.

## First run

1. Flash, open the Serial Monitor, plug in the tablet. Expect:
   ```
   PaperSync relay, protocol v3
   [ble] advertising as "PaperSync Pen"
   [usb] waiting for the tablet
   [usb] device 08F2:6811
   [usb] interface 1, endpoint 84, packet 64, descriptor 200 bytes
   [usb] interface 2, endpoint 86, packet 8, descriptor 228 bytes
   [usb] reading 2 HID interfaces
   ```
   (Measured on the board on 2026-10-18.) Two `USBH: Dev 1 EP 0 STALL`
   lines are normal: the tablet refuses SET_IDLE. A descriptor size of -1
   means the descriptor read failed, and that line is the one to send.
   Hover the pen over the tablet: the first five reports print as
   `[usb] report: 05 C0 ...`.
2. Every 5 seconds a `[stat]` line shows the tablet, the phone, the link MTU,
   the records waiting and the sequence number. `[ble] link MTU` prints when
   the phone or browser raises it, and a disconnect prints its reason code.
   An MTU of 23 (common in browsers) is fine: reports then go one per
   notification. Moving the pen over the tablet should
   raise the sequence number.
3. The relay does not show in Android's Bluetooth settings. It is a Bluetooth
   Low Energy device that only the app connects to. In the app, set Settings,
   Connection to Bluetooth, then connect "PaperSync Pen" from the Pen screen. Open
   a live page and write. Press a tablet button to check the buttons.
   The readout under the status line shows the relay:
   - `Bluetooth: connected, N relay notifications, N pen samples`: the
     counts should climb while the pen moves over the tablet.
   - `Pen from: 0x0 id 5`: the app is reading Report ID 5.
   - `Layouts: 484 bytes, id 5: ...`: the descriptors arrived whole. A
     small byte count or "no pen report found" means the long read was cut.
   - `Buttons:` the last presses, such as `undo`.
   The Pen screen shows the same readout with two more lines: the raw bytes
   of the last report, and counts of replayed and unreadable records.
4. To test the buffer: write with the phone's Bluetooth off, turn it back on,
   and the strokes should arrive marked as replayed.
