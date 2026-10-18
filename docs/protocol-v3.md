# PaperSync protocol v3: the relay

The ESP32 reads the tablet over USB and forwards the tablet's own HID reports
to the phone over Bluetooth, unchanged. It does not decode positions, scale
them or know the button map. The app decodes the reports with the same code it
uses for the USB cable (`app/lib/usb/pen_report_reader.dart`), so report
layouts, the portrait turn, corner calibration and the buttons are in one
place.

v3 keeps the v1 header and its guarantees (order, loss detection, replay,
device time). Only the records change. The app still accepts v1, so the
simulator and older firmware keep working.

The firmware is `firmware/papersync_relay/`. The app side is
`app/lib/protocol/relay_codec.dart`, `app/lib/usb/relay_decoder.dart` and
`app/lib/platform/relay_pen_transport.dart`.

## Why

On the phone and on the ESP32 alike, the tablet sends its pen as Report ID 5
on endpoint `0x86` (8 bytes, 0 to 4095, already portrait) and nothing on
`0x84`, where Windows gets Report ID 9. Its six buttons are keyboard keys,
Report ID 2, on the same endpoint. v2 assumed a fixed 10 byte Report ID 9
record and had no room for the buttons.

## GATT

| Role | UUID | Properties |
| --- | --- | --- |
| PaperSync service | `6f0c2d14-8a3e-4b7c-9d51-2e8f0a6b4c93` | |
| Stroke characteristic | `c4a91e70-15d2-4f6b-8a03-9b7e2d5c1f48` | notify |
| Report descriptor characteristic | `5b2e8d61-3c7a-4f19-b0d4-8e6a1f2c7d35` | read, notify |

The service and stroke ids are the v1 ones. The report descriptor
characteristic is new:

- Its value is the HID report descriptor of every forwarded interface, back
  to back in interface order, at most 512 bytes. Empty while no tablet is
  plugged in.
- The app reads it on connect, before it subscribes to the stroke
  characteristic.
- When the tablet is plugged in or out, the firmware notifies it. A
  notification carries only one packet, so it only means "changed": the app
  reads the whole value again.

## Notification

Little endian. At most 512 bytes, and never more than the link's MTU minus 3.

### Header (12 bytes)

| Offset | Type | Field |
| --- | --- | --- |
| 0 | `u8` | `version`, `3` |
| 1 | `u8` | `header_flags`, below |
| 2 | `u16` | `boot_id`, random per power on |
| 4 | `u32` | `first_seq`, sequence number of the first record |
| 8 | `u32` | `base_time_ms`, device uptime of the first record |

Header flags:

| Bit | Mask | Meaning |
| --- | --- | --- |
| 0 | `0x01` | Replayed: read while no phone was listening |
| 1 | `0x02` | Page button: a new page starts before the first record. With no records, before the next pen record |
| 2 | `0x04` | Control: the records are not pen samples |

### Record

| Offset | Type | Field |
| --- | --- | --- |
| 0 | `u8` | `dt_ms`, milliseconds after `base_time_ms` |
| 1 | `u8` | `length`, 1 to 64 |
| 2 | `length` bytes | The report exactly as the tablet sent it. Byte 0 is the report id |

A record whose length is 0, over 64, or past the end of the packet ends the
notification. The records before it are kept.

## Pen and control notifications

- A **pen notification** (control bit clear) holds pen reports, Report ID 5
  or 9. Record `i` has sequence number `first_seq + i`. The firmware buffers
  these while no phone listens and replays them, with the replay bit, after a
  reconnect. One notification never mixes replayed and live records.
- A **control notification** (control bit set) holds any other report, such
  as the buttons' keyboard report, press and release alike. `first_seq` is 0
  and means nothing. Control reports are sent only while a phone listens and
  are never buffered: a button press replayed minutes later would surprise.

The firmware decides pen or control by the report id only (`PEN_REPORT_IDS`
in the sketch).

## Firmware rules

- Read each interrupt IN endpoint with transfers of exactly one max packet,
  so one transfer is one report.
- Send a live notification when it holds 17 records or its first record is
  15 ms old. Keep notifications at least 7 ms apart.
- The records in one notification have consecutive sequence numbers and lie
  within 255 ms of the first. A record that starts a new page starts a new
  notification.
- When the buffer is full, drop the oldest record. The app sees the gap.

## How the app reads it

`RelayDecoder` turns each pen notification into v1 samples with the same
`boot_id`, sequence numbers, time and replay bit, so the capture code needs no
change. A record that holds no readable pen report leaves a sequence gap,
which the capture code counts as lost. Control records go through the key
decoder and become button presses, the same as on the cable.

Bluetooth does not say which tablet sits behind the relay, so the app uses
the Lumispark T605 profile.

## Test vector

A live pen notification from boot `0x1234`, sequence 100, time 5000 ms, with
one hovering Report ID 5:

```
03 00 34 12 64 00 00 00 88 13 00 00   header
00 08 05 c0 ba 0a ec 09 00 00         record: dt 0, length 8, the report
```
