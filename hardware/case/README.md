# PaperSync relay case

A tray the same size as the T605 (160 x 252 mm), 21 mm tall with the lid.
The lid velcros to the back of the tablet. The tray floor faces the desk.

![layout](layout.png)

## Files

| File | What it is |
| --- | --- |
| `case.py` | The model. Every size is a named value at the top. Edit and rerun. |
| `layout.png` | Top view for review, tablet face up, port edge at the bottom. |
| `stl/tray.stl`, `stl/lid.stl` | Whole parts. Need a bed of at least 256 mm (Bambu A1, P1S, X1). |
| `stl/*_half.stl`, `stl/splice_plate.stl` | Halves for smaller beds (Ender 3 and similar), joined with glue and two splice plates inside the tray. |
| `stl/strap_*.stl` | One strap per board (two for the LiPo). |

Regenerate after editing: `pip install manifold3d trimesh matplotlib`, then
`python3 case.py --split`.

## Layout

- **ESP32-S3**: bottom middle, both USB-C ports facing the bottom edge. The
  tablet cable plugs in there, and the second port stays reachable for
  reflashing without opening the case.
- **TP4056**: bottom left, charging port on the left edge.
- **Switch**: left edge, just above the charging port. Lies on its side with
  the slider poking out through a 5 x 2.9 mm slot.
- **MT3608**: between the TP4056 and the ESP32, so the 5 V wire is short.
- **LiPo**: above the boards, held by two straps. Nothing screws through it.
- The left edge is free for your hand only if you write right-handed; the
  switch and charger sit there because they are only used before and after.

## How parts are held

None of these boards have mounting holes, so each one sits in a 3 mm tall
pocket and a printed strap screws down over it onto two posts. Put a strip of
1 mm foam tape (or double-sided foam tape) on the underside of each strap. It
takes up small measuring errors and stops rattling.

## Hardware

- 7 x M3 x 8 countersunk self-tapping screws (lid). The heads sit flush, so
  nothing presses into the tablet.
- 12 x M2 x 6 self-tapping screws (straps).
- 4 x 10 mm stick-on rubber bumpers (recesses under the tray).
- Foam tape, velcro strips (two long strips along the lid edges work well).

## Print settings

PLA or PETG, 0.2 mm layers, 3 walls, 20 % infill. Print the tray floor down
and the lid lip up. No supports needed. A light colour lets the TP4056
charging LED glow through the case.

## Check before printing

These were guessed from the caliper sizes, so check them against your parts:

1. **ESP32 port height**: the slot runs 2 to 14 mm above the floor. With the
   header pins pointing down, the board sits on its pins.
2. **Switch slider**: the slot is 5 mm long and 2.9 mm tall. File it wider if
   the slider rubs.
3. **Tablet port position**: the ESP32 is centred on the bottom edge. If the
   tablet's own port is near a corner, move it with `PARTS["ESP32-S3"]["pos"]`
   so the cable stays short.
