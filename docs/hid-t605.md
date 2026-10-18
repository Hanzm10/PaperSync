# T605 tablet HID reference

Tablet: Lumispark T605 / VINSA T605 (same hardware, made by Gotop Information). Sources: Wireshark USBPcap captures of the real tablet, its HID report descriptor, and hardware tests. The corner values are measured. Anything still unmeasured is marked PENDING.

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
| HID, 256 byte report descriptor | interrupt IN `0x86` | Vendor (ID 1), Keyboard (ID 2), Digitizer (ID 5), Consumer (ID 4) | ID 5 is the lower fidelity pen report. On an Android phone, the tablet was seen to send the pen here and nothing on `0x84`, so the app reads both and decodes ID 5 from this descriptor when ID 9 is absent |

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

## Millimetres, corners and orientation: measured

Measured with `papersync_corner_calibration.py`, tip pressed, all four corners and edges.

| | Min | Max | Min is at |
| --- | --- | --- | --- |
| X | 0 | 32759 | Left edge |
| Y | 0 | 32759 | Top edge |

- The tablet uses nearly all of its logical range and clamps at the edges, so values never leave 0 to 32759.
- X works out to about 193 counts per mm (about 4900 LPI), close to the marketed 5080 LPI.
- **X and Y have different scales.** The same 0 to 32759 range covers 170 mm across X and 107 mm down Y. Scale each axis separately or drawings come out stretched:

```
x_mm = x / 32759 * 170
y_mm = y / 32759 * 107
```

- **Orientation:** (0, 0) is the top left corner, X grows to the right and Y grows downward, with the tablet held the way the user holds it to write. That matches screen and Flutter canvas coordinates, so no flip or rotation is needed.
- The printed corner marks pressed with the pen read: top left x 138, y 147; bottom right x 32253, y 32759. In millimetres that is about (0.7, 0.5) and (167.4, 107).
- Keep the min, max and mm values as constants in `lumisparkT605`, not inline.
- The descriptor's physical size does not match the marketed area, so do not use it for millimetres.

## Tilt is unreliable

Tilt read (85, -82) at one corner and (0, 0) at another while the pen was held normally. Treat it as optional. The app decodes it but stores nothing from it, and no feature should depend on it.

## Other tablet facts

Active area 170 by 107 mm, centered on a 252 by 160 by 5 mm body. Hover height 15 mm. About 330 reports per second. Marketed at 5080 LPI.

## Report ID 5 on a phone and on the ESP32: measured

The ESP32-S3 as USB host (esp32 core 3.0.7) sees the same thing as the phone: interface 1 on `0x84` (max packet 64) is silent, interface 2 on `0x86` (max packet 8) streams Report ID 5, for example `05 C0 BA 0A EC 09 00 00`. The phone app already reads every interface's report descriptor and sends SET_IDLE, and `0x84` stayed silent, so those two steps alone do not wake Report ID 9.


On an Android phone (Samsung A07, USB OTG) the tablet sends no Report ID 9 at all. The pen arrives as Report ID 5 on endpoint `0x86`:

- 8 bytes per report: id `05`, flags, X (16 bit), Y (16 bit), pressure (16 bit). Example: `05 c0 ff 0f 02 00 00 00`.
- Each interrupt transfer packs two reports back to back, so a transfer is cut into reports by the size the report descriptor gives. Reading only the first drops half the points.
- The report is already portrait, made for a phone screen: X runs across the short side and Y down the long side, with the buttons and the port along the bottom. Report ID 9 is landscape. The app turns Report ID 5 back into the landscape frame, so the default orientation (buttons along the bottom) shows it exactly as sent.

### Report ID 5 corners: measured

Pen tip held on each printed corner mark, tablet held as the page (buttons along the bottom):

| Corner mark | X | Y |
| --- | --- | --- |
| Top left | 0 | 167 |
| Top right | 4095 | 110 |
| Bottom left | 0 | 4059 |
| Bottom right | 4095 | 4095 |

- Across, the report is already at its limits at the marks, so X uses 0 to 4095.
- Down, the marks sit at about 139 and 4077, so Y uses that range and the strip above the top marks stays on the top edge.
- Stored as `phoneCorners` in `lumisparkT605`.

## Buttons on a phone: measured

The six buttons send Report ID 2, a keyboard report, on endpoint `0x86`. Each report is 8 bytes: id `02`, modifiers, a reserved byte, then the keys held. A transfer usually packs the press and its release back to back, for example `02 01 00 2d 00 00 00 00 | 02 00 00 00 00 00 00 00`.

With the tablet held as the page (buttons along the bottom), the left rocker is beside the port:

| Rocker | End | Sends | App action |
| --- | --- | --- | --- |
| Left | top | Ctrl and `=` (`0x2E`) | Redo |
| Left | bottom | Ctrl and `-` (`0x2D`) | Undo |
| Middle | top | `]` (`0x30`) | Zoom in |
| Middle | bottom | `[` (`0x2F`) | Zoom out |
| Right | top | Space (`0x2C`) | Next page (new after the last) |
| Right | bottom | Tab (`0x2B`) | Previous page |

The pen's two buttons send the same keyboard report, both with the Z key, told apart by the modifiers (measured 2026-10-18):

| Pen button | Sends | App action |
| --- | --- | --- |
| − | Ctrl and Z (`02 01 00 1d`) | Erase while held |
| + | Ctrl, Shift and Z (`02 03 00 1d`) | Next color, double press opens the picker |

They do not change the pen report's flag byte. The tablet's buttons match on the key code alone. The pen's buttons match on the key and the modifiers (`t605Chords`). A press is a key that was not held in the report before, so holding a button counts once. The mapping lives in `t605Keys` in `app/lib/usb/tablet_keys.dart`.
