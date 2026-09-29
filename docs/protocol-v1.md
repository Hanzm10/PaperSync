# PaperSync protocol v1

This is the Bluetooth contract between the pen and the phone. The firmware
adopts the UUIDs and the byte layout below. A later `spec.yaml` generator
replaces the hand-written constants in `app/lib/protocol/constants.dart`;
until then those constants and this file are the same contract.

## GATT

| Role | UUID |
| --- | --- |
| PaperSync service | `6f0c2d14-8a3e-4b7c-9d51-2e8f0a6b4c93` |
| Stroke characteristic (notify) | `c4a91e70-15d2-4f6b-8a03-9b7e2d5c1f48` |
| Battery Service | `0x180F` (`0000180f-0000-1000-8000-00805f9b34fb`) |
| Battery Level | `0x2A19` (`00002a19-0000-1000-8000-00805f9b34fb`) |

The phone connects only to a device that advertises the PaperSync service.
Battery is the standard Battery Service, not a field in the stroke stream.

## Units

- Positions are `1/200` mm. `xMm = x / 200` and `yMm = y / 200`.
- The active area is 170 mm by 107 mm.
- Pressure is `0..16383`. A larger value on the wire is clamped to 16383.
- Time is milliseconds of device uptime. See below.

## Notification

Little-endian. A notification is one 12-byte header followed by zero or more
8-byte records. Anything longer than 512 bytes is rejected. A trailing partial
record is dropped and counted; it does not fail the samples before it.

### Header (12 bytes)

| Offset | Type | Field |
| --- | --- | --- |
| 0 | `u8` | `version`. Only `1` is accepted. |
| 1 | `u8` | `header_flags`. Bit 0 (`0x01`) means the samples were replayed from the pen buffer. Other bits are ignored. |
| 2 | `u16` | `boot_id`. A random value chosen once per power-on. |
| 4 | `u32` | `first_seq`. Sequence number of the first record in this notification. |
| 8 | `u32` | `base_time_ms`. Device uptime, in milliseconds, that record offsets are added to. |

### Record (8 bytes)

| Offset | Type | Field |
| --- | --- | --- |
| 0 | `u16` | `x` |
| 2 | `u16` | `y` |
| 4 | `u16` | `pressure` (`0..16383`; higher values are clamped) |
| 6 | `u8` | `flags` |
| 7 | `u8` | `dt_ms` |

Flag bits:

| Bit | Mask | Meaning |
| --- | --- | --- |
| 0 | `0x01` | touching |
| 1 | `0x02` | hover |
| 2 | `0x04` | page marker (the pen sends this when the page button is pressed) |

Unknown flag bits are ignored. They do not reject the packet, and they are
kept on the sample so a newer sender is not stripped by an older decoder.

## Sequence, boot, and time

- `seq` of record `i` is `first_seq + i`. A gap inside one `boot_id` means
  samples were lost.
- `tDeviceMs` of a record is `base_time_ms + dt_ms`. `dt_ms` is an offset from
  the header, not a delta from the previous record. It is one byte, so the
  firmware starts a new notification before the offset would pass 255.
- `boot_id` scopes both the sequence and the uptime clock. After a reboot the
  sequence and the clock start again. A replay from another boot is not the
  same timeline as live samples from the current boot.

## Size

One notification is at most 512 bytes, which is 62 records after the header
(`(512 - 12) / 8`). The decoder refuses a longer packet and never throws.
Stroke and page caps are applied when capture is built; they are not part of
the wire format.
