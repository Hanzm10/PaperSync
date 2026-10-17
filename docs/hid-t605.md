# T605 tablet HID reference

Tablet: Lumispark T605 / VINSA T605 (same hardware, made by Gotop Information). Sources: Wireshark USBPcap captures of the real tablet, its HID report descriptor, and hardware tests. Anything not measured yet is marked PENDING.

In code: `app/lib/usb/hid_report.dart` decodes a report and `app/lib/usb/tablet_profile.dart` holds the IDs and corner values.

## USB identity

| Field | Value |
| --- | --- |
| idVendor | `0x08F2` (Gotop Information) |
| idProduct | `0x6811` |
| bcdDevice | `0x2024` |
| bcdUSB | `0x0200` |
| bMaxPacketSize0 | 64 |
| Configurations | 1 |

Raw device descriptor: `12 01 00 02 00 00 00 40 f2 08 11 68 24 20 01 02 03 01`

## The tablet is a composite device

At one enumeration (device address 8) it exposed three things:

| Interface | Endpoint | What it is | Use |
| --- | --- | --- | --- |
| USB mass storage | bulk `0x02` and `0x83` | Likely a virtual driver drive, SCSI traffic | Ignore. Claim nothing here |
| HID, 228 byte report descriptor | interrupt IN `0x84` | Vendor (ID 6), Mouse (ID 3), Digitizer (ID 9) | Read this one |
| HID, 256 byte report descriptor | interrupt IN `0x86` | Vendor (ID 1), Keyboard (ID 2), Digitizer (ID 5), Consumer (ID 4) | Ignore. ID 5 is the lower fidelity pen report |

Windows sends SET_IDLE to each HID interface before reading. Claim only HID class (`0x03`) interfaces.

The interface on `0x84` also carries vendor and mouse reports, so the first byte of each interrupt transfer must be checked. Only `0x09` is a pen report. Everything else is dropped and counted.

## Report ID 9

10 bytes, little endian.

| Byte | Field | Notes |
| --- | --- | --- |
| 0 | Report ID | Always `0x09` |
| 1 | Flags | bit 0 tip, bit 1 barrel, bit 2 eraser, bits 3 to 5 constant, bit 6 in range, bit 7 constant (sent as 1) |
| 2 to 3 | X | u16, logical 0 to 32767 |
| 4 to 5 | Y | u16, logical 0 to 32767 |
| 6 to 7 | Pressure | u16, 0 to 16383 |
| 8 | X tilt | i8, -127 to 127 (usage `0x3D`) |
| 9 | Y tilt | i8, -127 to 127 (usage `0x3E`) |

- Mask the flags with `0x47` before reading them. Bit 7 is constant padding that the tablet sets to 1 in every report.
- Bytes 8 and 9 are X tilt and Y tilt, not azimuth and altitude (those would be usages `0x3F` and `0x40`). Earlier notes called them azimuth and altitude, which was wrong.
- The descriptor declares no angle unit. Treat tilt as relative. It is not verified that it is degrees.
- Decide contact from the tip bit, never from pressure. A hovering pen can report a small pressure with the tip up.

## Test vectors

Used by `app/test/usb/hid_report_test.dart`.

| Hex | Tip | In range | X | Y | Pressure | Tilt X / Y |
| --- | --- | --- | --- | --- | --- | --- |
| `09c0fe3d505c1d00e3e5` | 0 | 1 | 15870 | 23632 | 29 | -29 / -27 |
| `09c1b837334d9505aefb` | 1 | 1 | 14264 | 19763 | 1429 | -82 / -5 |

## Millimetres and corner values: PENDING

Both axes report 0 to 32767, but the real active area may not span all of it, and the descriptor's physical size does not match the marketed 170 by 107 mm. So millimetres come from measured corners:

```
x_mm = (x - xMin) / (xMax - xMin) * 170
y_mm = (y - yMin) / (yMax - yMin) * 107
```

| | Min | Max |
| --- | --- | --- |
| X | PENDING | PENDING |
| Y | PENDING | PENDING |

Measure with `papersync_corner_calibration.py` (laptop and tshark, no ESP32 needed). Until then the profile uses 0 to 32767, and the four values stay in `lumisparkT605` so a measurement is a one line change with `withCorners`.

## Other tablet facts

Active area 170 by 107 mm, centered on a 252 by 160 by 5 mm body. Hover height 15 mm. About 330 reports per second. Marketed at 5080 LPI.
