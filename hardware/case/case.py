"""PaperSync relay case: a tray the size of the T605 that velcros to its back.

Run:  pip install build123d matplotlib
      python3 case.py            # writes step/, stl/ and layout.png
      python3 case.py --split    # also writes half parts for beds under 256 mm

All sizes are millimetres. The view is from above with the tablet face up and
its port and buttons at the bottom, so left and right match what you see.
x runs across the tablet (0..160), y runs up it (0..252), z is height.

Every board sits on the floor inside a low locating pocket and is held down by
a printed strap screwed onto two posts. A strip of foam tape under the strap
takes up small measuring errors, so no board needs mounting holes.
"""

import argparse
import os

from build123d import (Align, Box, Cone, Cylinder, Pos, RectangleRounded, export_step,
                       export_stl, extrude)

MIN = (Align.MIN, Align.MIN, Align.MIN)

# ---- Case -------------------------------------------------------------------
# Tablet is 160 x 252. The case is 12 mm shorter so it prints on a 200 x 250
# bed; it lines up with the tablet's bottom edge and stops short at the top.
WIDTH, LENGTH = 160.0, 240.0
CORNER_R = 8.0
WALL = 2.5
FLOOR = 2.0
INNER_H = 16.5  # tallest stack: ESP32 12.8 + foam 1.0 + strap 2.0 + spare
LID = 2.5
LIP_H, LIP_W, LIP_GAP = 1.5, 1.2, 0.3  # lid lip that keys into the tray

# Lid screws: M2 x 10 countersunk (flat head), self-tapping into the posts.
LID_POST_D, LID_PILOT_D, LID_HOLE_D, LID_HEAD_D = 7.0, 1.8, 2.4, 4.2
LID_PILOT_DEPTH = 10.0
# Every screw hole keeps this much solid floor under it, so no tip pokes out.
FLOOR_UNDER_HOLE = 0.8
LID_POSTS = [
    (WALL + 3.0, WALL + 3.0), (WIDTH - WALL - 3.0, WALL + 3.0),
    (WALL + 3.0, LENGTH - WALL - 3.0), (WIDTH - WALL - 3.0, LENGTH - WALL - 3.0),
    (WALL + 3.0, LENGTH / 2), (WIDTH - WALL - 3.0, LENGTH / 2),
    (WIDTH / 2, LENGTH - WALL - 3.0),
]

# Rubber feet recesses under the tray (10 mm stick-on bumpers).
FEET = [(18, 18), (WIDTH - 18, 18), (18, LENGTH - 18), (WIDTH - 18, LENGTH - 18)]
FOOT_D, FOOT_DEPTH = 10.5, 0.8

# ---- Parts (measured with calipers) ------------------------------------------
# name: (x, y) lower-left corner, (size x, size y, height), strap axis
#   strap "x" runs across the part left to right at strap_at (a y offset),
#   strap "y" runs along it bottom to top at strap_at (an x offset).
POCKET_GAP, POCKET_WALL, POCKET_H = 0.5, 1.2, 3.0
FOAM, STRAP_T, STRAP_W = 1.0, 2.0, 8.0
STRAP_POST_D, STRAP_PILOT_D, STRAP_HOLE_D = 6.0, 1.8, 2.4  # M2 self-tapping
STRAP_HEAD_H, STRAP_HEAD_RECESS_D = 1.6, 6.5  # M2 pan head; lid recess if it would touch

PARTS = {
    # Ports face the left edge, next to the tablet's own port, so the tablet
    # cable stays short. The second USB-C port stays reachable for reflashing.
    "ESP32-S3": dict(pos=(WALL + 0.5, 40.0), size=(70.6, 20.6, 12.8),
                     strap=("y", 52.0), open_side="left"),
    # Charging port faces the bottom edge, in the middle.
    "TP4056": dict(pos=(80.0 - 17.5 / 2, WALL + 0.5), size=(17.5, 28.8, 11.2),
                   strap=("x", 18.0), open_side="bottom"),
    # Lies on its side, slider pointing out through the left wall.
    "Switch": dict(pos=(WALL, 75.0), size=(6.0, 8.5, 3.7),
                   strap=("y", 4.5), open_side="left"),
    "MT3608": dict(pos=(25.0, 76.0), size=(37.4, 12.1, 2.0),
                   strap=("y", 18.7), open_side=None),
    "LiPo": dict(pos=(20.0, 105.0), size=(37.2, 60.9, 4.7),
                 strap=("x", 15.0), strap2=("x", 44.0), open_side=None),
}

# Size of the fit-test corner piece (x, y), measured from the bottom-left.
TEST_SIZE = (100.0, 100.0)

# Wall cutouts: (wall, centre along that wall, width, z from floor, height)
CUTOUTS = {
    "ESP32 USB-C x2": ("left", 40.0 + 20.6 / 2, 23.0, 2.0, 12.0),
    "TP4056 USB-C": ("bottom", 80.0, 12.0, 0.5, 7.5),
    "Switch slider": ("left", 75.0 + 8.5 / 2, 5.0, 0.4, 2.9),
}


def slab(x, y, w, h, r, z, height):
    """Rounded rectangle with its lower-left corner at (x, y), extruded up from z."""
    face = Pos(x, y, z) * RectangleRounded(w, h, r, align=(Align.MIN, Align.MIN))
    return extrude(face, amount=height)


def box(x, y, z, sx, sy, sz):
    return Pos(x, y, z) * Box(sx, sy, sz, align=MIN)


def cyl(x, y, z, d, h):
    return Pos(x, y, z) * Cylinder(d / 2, h, align=(Align.CENTER, Align.CENTER, Align.MIN))


def straps():
    """Yields (part name, strap rectangle (x0, y0, x1, y1), post centres, strap z)."""
    for name, p in PARTS.items():
        (x, y), (sx, sy, sz) = p["pos"], p["size"]
        z = FLOOR + sz + FOAM
        for key in ("strap", "strap2"):
            if key not in p:
                continue
            axis, at = p[key]
            reach = STRAP_POST_D / 2 + POCKET_GAP + POCKET_WALL + 1.0
            if axis == "x":
                cy = y + at
                posts = [(x - reach, cy), (x + sx + reach, cy)]
                rect = (x - reach - 4, cy - STRAP_W / 2, x + sx + reach + 4, cy + STRAP_W / 2)
            else:
                cx = x + at
                posts = [(cx, y - reach), (cx, y + sy + reach)]
                rect = (cx - STRAP_W / 2, y - reach - 4, cx + STRAP_W / 2, y + sy + reach + 4)
            yield name, rect, posts, z


def tray():
    shell = slab(0, 0, WIDTH, LENGTH, CORNER_R, 0, FLOOR + INNER_H)
    body = shell - slab(WALL, WALL, WIDTH - 2 * WALL, LENGTH - 2 * WALL, CORNER_R - WALL,
                        FLOOR, INNER_H + 1)

    for x, y in LID_POSTS:
        body += cyl(x, y, 0, LID_POST_D, FLOOR + INNER_H)
        body -= cyl(x, y, FLOOR + INNER_H - LID_PILOT_DEPTH, LID_PILOT_D, LID_PILOT_DEPTH + 1)

    # Locating pockets: a low rim around each part, open where a port or
    # slider has to reach the wall.
    for name, p in PARTS.items():
        (x, y), (sx, sy, _) = p["pos"], p["size"]
        g, t = POCKET_GAP, POCKET_WALL
        rim = box(x - g - t, y - g - t, FLOOR, sx + 2 * (g + t), sy + 2 * (g + t), POCKET_H)
        rim -= box(x - g, y - g, FLOOR - 0.1, sx + 2 * g, sy + 2 * g, POCKET_H + 1)
        side = p["open_side"]
        if side == "bottom":
            rim -= box(x - g, y - 10, FLOOR - 0.1, sx + 2 * g, 10 + g, POCKET_H + 1)
        elif side == "left":
            rim -= box(x - 10, y - g, FLOOR - 0.1, 10 + g, sy + 2 * g, POCKET_H + 1)
        body += rim

    for _, _, posts, z in straps():
        for px, py in posts:
            body += cyl(px, py, 0, STRAP_POST_D, z)
            bottom = max(z - 8, FLOOR_UNDER_HOLE)
            body -= cyl(px, py, bottom, STRAP_PILOT_D, z - bottom + 1)

    # Keep strap posts and pockets inside the shell (posts near a wall merge
    # into it, which is fine, but must not poke out of it).
    body = body & shell

    for _, (wall, c, w, z, h) in CUTOUTS.items():
        if wall == "bottom":
            body -= box(c - w / 2, -1, FLOOR + z, w, WALL + 2, h)
        elif wall == "left":
            body -= box(-1, c - w / 2, FLOOR + z, WALL + 2, w, h)

    for x, y in FEET:
        body -= cyl(x, y, -0.1, FOOT_D, FOOT_DEPTH + 0.1)
    return body


def lid():
    plate = slab(0, 0, WIDTH, LENGTH, CORNER_R, 0, LID)
    o, i = WALL + LIP_GAP, WALL + LIP_GAP + LIP_W
    lip = (slab(o, o, WIDTH - 2 * o, LENGTH - 2 * o, CORNER_R - o, LID, LIP_H)
           - slab(i, i, WIDTH - 2 * i, LENGTH - 2 * i, CORNER_R - i, LID - 1, LIP_H + 2))
    for x, y in LID_POSTS:
        lip -= cyl(x, y, LID - 0.1, LID_POST_D + 1.0, LIP_H + 1)
    body = plate + lip
    for x, y in LID_POSTS:
        body -= cyl(x, y, -1, LID_HOLE_D, LID + 2)
        # Countersink on the outer face (z = 0), which goes against the tablet.
        body -= Pos(x, y, -0.01) * Cone(LID_HEAD_D / 2, LID_HOLE_D / 2,
                                         (LID_HEAD_D - LID_HOLE_D) / 2,
                                         align=(Align.CENTER, Align.CENTER, Align.MIN))
    # Where a strap screw head would touch the lid, sink a shallow recess into
    # the lid's inner face. Mirrored too (x -> WIDTH - x), because the lid is
    # flipped over to fit and either way round should clear.
    top = FLOOR + INNER_H
    for _, _, posts, z in straps():
        depth = z + STRAP_T + STRAP_HEAD_H + 0.3 - top
        if depth <= 0:
            continue
        for px, py in posts:
            for x in (px, WIDTH - px):
                body -= cyl(x, py, LID - depth, STRAP_HEAD_RECESS_D, depth + 1)
    # Printed lip-up; flipped over it sits on the tray with the lip inside.
    return body


def strap_part(rect, posts):
    x0, y0, x1, y1 = rect
    s = box(0, 0, 0, x1 - x0, y1 - y0, STRAP_T)
    for px, py in posts:
        s -= cyl(px - x0, py - y0, -1, STRAP_HOLE_D, STRAP_T + 2)
    return s


def splice():
    """Plate glued across the seam inside the tray when it is printed in halves."""
    return box(0, 0, 0, 40.0, 24.0, 2.0)


def save(part, out, name):
    """Writes name.step (editable solid, for Fusion) and name.stl (for the slicer)."""
    export_step(part, os.path.join(out, "step", f"{name}.step"))
    export_stl(part, os.path.join(out, "stl", f"{name}.stl"), tolerance=0.01,
               angular_tolerance=0.2)


def layout_png(path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Circle, FancyBboxPatch, Rectangle

    fig, ax = plt.subplots(figsize=(7, 10.5))
    ax.add_patch(FancyBboxPatch((CORNER_R, CORNER_R), WIDTH - 2 * CORNER_R, LENGTH - 2 * CORNER_R,
                                boxstyle=f"round,pad={CORNER_R}", fc="#f4f4f4", ec="#333", lw=2))
    colors = {"ESP32-S3": "#4a7bd0", "TP4056": "#d0644a", "MT3608": "#8a4ad0",
              "Switch": "#2a9d55", "LiPo": "#d0a64a"}
    for name, p in PARTS.items():
        (x, y), (sx, sy, sz) = p["pos"], p["size"]
        ax.add_patch(Rectangle((x, y), sx, sy, fc=colors[name], ec="#222", alpha=0.75))
        label = f"{name}\n{sx:g}x{sy:g}x{sz:g}"
        if min(sx, sy) < 20:  # too narrow to hold its own label
            lift = 22 if sy < 15 else 6
            ax.annotate(label, (x + sx, y + sy / 2), (x + sx + 22, y + sy / 2 + lift), fontsize=7,
                        va="center", arrowprops=dict(arrowstyle="-", color="#444"))
            continue
        ax.text(x + sx / 2, y + sy / 2, label, ha="center", va="center", fontsize=6.5,
                color="white", weight="bold", rotation=90 if sy > 1.5 * sx else 0)
    for _, rect, posts, _ in straps():
        x0, y0, x1, y1 = rect
        ax.add_patch(Rectangle((x0, y0), x1 - x0, y1 - y0, fc="none", ec="#555", ls="--", lw=1))
        for px, py in posts:
            ax.add_patch(Circle((px, py), STRAP_POST_D / 2, fc="#999", ec="#333"))
    for x, y in LID_POSTS:
        ax.add_patch(Circle((x, y), LID_POST_D / 2, fc="#666", ec="#222"))
    for label, (wall, c, w, _, _) in CUTOUTS.items():
        if wall == "bottom":
            ax.add_patch(Rectangle((c - w / 2, -3), w, 4, fc="red"))
            ax.annotate(label, (c, -3), (c, -18), ha="center", fontsize=8, color="red",
                        arrowprops=dict(arrowstyle="->", color="red"))
        else:
            ax.add_patch(Rectangle((-3, c - w / 2), 4, w, fc="red"))
            ax.annotate(label, (-3, c), (-50, c), va="center", ha="right", fontsize=8,
                        color="red", arrowprops=dict(arrowstyle="->", color="red"))
    ax.text(WIDTH / 2 + 20, LENGTH - 50, "empty\n(room for wiring)", ha="center", color="#aaa")
    ax.text(WIDTH / 2, -30, "BOTTOM EDGE (lines up with the tablet's bottom edge)", ha="center", fontsize=9)
    ax.text(WIDTH / 2, LENGTH + 6, f"Top view, tablet face up.  {WIDTH:g} x {LENGTH:g} x "
            f"{FLOOR + INNER_H + LID:g} mm", ha="center", fontsize=9)
    ax.set_xlim(-110, WIDTH + 10)
    ax.set_ylim(-40, LENGTH + 15)
    ax.set_aspect("equal")
    ax.axis("off")
    fig.savefig(path, dpi=150, bbox_inches="tight")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--split", action="store_true", help="also write halves for small beds")
    args = ap.parse_args()
    here = os.path.dirname(os.path.abspath(__file__))
    for folder in ("step", "stl"):
        os.makedirs(os.path.join(here, folder), exist_ok=True)

    t, l = tray(), lid()
    save(t, here, "tray")
    save(l, here, "lid")
    for i, (name, rect, posts, _) in enumerate(straps()):
        save(strap_part(rect, posts), here, f"strap_{i + 1}_{name}")
    if args.split:
        far = 2 * LENGTH
        bottom = box(-10, -10, -10, WIDTH + 20, LENGTH / 2 + 10, 60)
        top = box(-10, LENGTH / 2, -10, WIDTH + 20, far, 60)
        for part, m in (("tray", t), ("lid", l)):
            save(m & bottom, here, f"{part}_bottom_half")
            save(m & top, here, f"{part}_top_half")
        save(splice(), here, "splice_plate")
    # Cheap fit test: the lower-left corner holding every board except the
    # LiPo, with the real ports, switch slot, pockets and strap posts.
    save(t & box(-1, -1, -1, TEST_SIZE[0] + 1, TEST_SIZE[1] + 1, 60), here, "test_corner")
    layout_png(os.path.join(here, "layout.png"))
    print(f"tray {t.volume / 1000:.0f} cm3, lid {l.volume / 1000:.0f} cm3, height "
          f"{FLOOR + INNER_H + LID:g} mm")


if __name__ == "__main__":
    main()
