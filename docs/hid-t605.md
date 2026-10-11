# T605 tablet HID reference

Tablet: Lumispark T605 / VINSA T605 (same hardware). Source: the PaperSync single source of truth document and one USBPcap capture taken on Windows.

## Capture facts

One captured interrupt packet (Wireshark frame 1491):

| Field | Value |
| --- | --- |
| Direction | device to host (IN) |
| USB bus, device address | 2, 10 |
| Endpoint | `0x84` (endpoint 4, IN) |
| Transfer type | interrupt |
| Interface class | HID (0x03) |
| Data length | 10 bytes |
| Status | success |

HID data: `09 c0 fe 3d 50 5c 1d 00 e3 e5`

The "time from request" shown by Wireshark (12.97 ms) is how long that one request waited, not the report interval. Do not derive the sample rate from it. The box and the SSOT give about 330 samples per second.

## Report ID 9 (the one to build against)

All multi-byte fields are little endian.

| Byte | Field | Type | Notes |
| --- | --- | --- | --- |
| 0 | Report ID | u8 | Always `0x09` |
| 1 | Flags | u8 | bit0 tip switch (touching), bit1 barrel switch, bit2 eraser, bit6 in range |
| 2 to 3 | X | u16 | Logical range 0 to 32767 |
| 4 to 5 | Y | u16 | Logical range 0 to 32767 |
| 6 to 7 | Pressure | u16 | 0 to 16383 |
| 8 | Tilt A | i8 | The SSOT calls it azimuth |
| 9 | Tilt B | i8 | The SSOT calls it altitude |

The tablet also exposes a second digitizer interface, Report ID 5 (8 bytes, 12 bit position, no tilt). Ignore it.

## Decoded sample

| Field | Raw | Value |
| --- | --- | --- |
| Flags | `0xC0` | in range, tip up, barrel up, eraser off, bit7 set |
| X | `fe 3d` | 15870 |
| Y | `50 5c` | 23632 |
| Pressure | `1d 00` | 29 |
| Byte 8 | `e3` | -29 |
| Byte 9 | `e5` | -27 |

Things this sample shows that the SSOT does not say:

- Bit 7 of the flags is set. The SSOT lists it as padding. Keep it, do not reject on it, and find out what it is.
- Pressure is 29 while the tip switch is clear. Decide touching from the tip switch, never from pressure above zero.
- Bytes 8 and 9 are close to each other and both negative. That looks more like X tilt and Y tilt in degrees than azimuth and altitude. Check the usage codes in the report descriptor (X tilt 0x3D, Y tilt 0x3E, azimuth 0x3F, altitude 0x40) before naming them in code.

## Still needed

- USB vendor id and product id (from the device descriptor frame in the capture, or the hardware id in Device Manager).
- The four corner raw values for X and Y. X and Y both report 0 to 32767, but the active area is 170 by 107 mm, so counts per millimetre differ per axis or Y does not use the full range. Calibrate each axis separately.
- Whether Android needs the SET_IDLE that Windows sent before reports flow.

Test vector for the codec: the 10 bytes above.
