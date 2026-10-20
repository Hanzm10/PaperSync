"""PaperSync relay case: a tray the size of the T605 that velcros to its back.

Run:  pip install manifold3d trimesh matplotlib
      python3 case.py            # writes stl/ and layout.png
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

import numpy as np
import trimesh
from manifold3d import CrossSection, JoinType, Manifold, set_circular_segments

set_circular_segments(48)

# ---- Case -------------------------------------------------------------------
WIDTH, LENGTH = 160.0, 252.0  # tablet footprint
CORNER_R = 8.0
WALL = 2.5
FLOOR = 2.0
INNER_H = 16.5  # tallest stack: ESP32 12.8 + foam 1.0 + strap 2.0 + spare
LID = 2.5
LIP_H, LIP_W, LIP_GAP = 1.5, 1.2, 0.3  # lid lip that keys into the tray

# Lid screws: M3 x 8 countersunk, self-tapping into the corner posts.
LID_POST_D, LID_PILOT_D, LID_HOLE_D, LID_HEAD_D = 7.0, 2.5, 3.4, 6.2
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

PARTS = {
    # Ports face the bottom edge: the tablet cable plugs in from there, and the
    # second USB-C port stays reachable for reflashing.
    "ESP32-S3": dict(pos=(69.7, WALL + 0.5), size=(20.6, 70.6, 12.8),
                     strap=("x", 52.0), open_side="bottom"),
    # Charging port faces the left edge.
    "TP4056": dict(pos=(WALL + 0.5, 20.0), size=(28.8, 17.5, 11.2),
                   strap=("y", 18.0), open_side="left"),
    "MT3608": dict(pos=(42.0, 20.0), size=(12.1, 37.4, 2.0),
                   strap=("x", 18.7), open_side=None),
    # Lies on its side, slider pointing out through the left wall.
    "Switch": dict(pos=(WALL, 50.0), size=(6.0, 8.5, 3.7),
                   strap=("y", 4.5), open_side="left"),
    "LiPo": dict(pos=(12.0, 72.0), size=(37.2, 60.9, 4.7),
                 strap=("x", 15.0), strap2=("x", 44.0), open_side=None),
}

# Wall cutouts: (wall, centre along that wall, width, z from floor, height)
CUTOUTS = {
    "ESP32 USB-C x2": ("bottom", 80.0, 23.0, 2.0, 12.0),
    "TP4056 USB-C": ("left", 20.0 + 17.5 / 2, 12.0, 0.5, 7.5),
    "Switch slider": ("left", 50.0 + 8.5 / 2, 5.0, 0.4, 2.9),
}


def rounded_rect(w, h, r):
    return CrossSection.square([w - 2 * r, h - 2 * r]).translate([r, r]).offset(r, JoinType.Round)


def box(x, y, z, sx, sy, sz):
    return Manifold.cube([sx, sy, sz]).translate([x, y, z])


def cyl(x, y, z, d, h):
    return Manifold.cylinder(h, d / 2).translate([x, y, z])


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
    outer = rounded_rect(WIDTH, LENGTH, CORNER_R)
    inner = rounded_rect(WIDTH - 2 * WALL, LENGTH - 2 * WALL, CORNER_R - WALL).translate([WALL, WALL])
    body = outer.extrude(FLOOR + INNER_H) - inner.extrude(INNER_H + 1).translate([0, 0, FLOOR])

    for x, y in LID_POSTS:
        body += cyl(x, y, 0, LID_POST_D, FLOOR + INNER_H)
        body -= cyl(x, y, FLOOR + INNER_H - 10, LID_PILOT_D, 11)

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
            body -= cyl(px, py, z - 8, STRAP_PILOT_D, 9)

    # Keep strap posts and pockets inside the shell (posts near a wall merge
    # into it, which is fine, but must not poke out of it).
    body = body ^ outer.extrude(FLOOR + INNER_H)

    for _, (wall, c, w, z, h) in CUTOUTS.items():
        if wall == "bottom":
            body -= box(c - w / 2, -1, FLOOR + z, w, WALL + 2, h)
        elif wall == "left":
            body -= box(-1, c - w / 2, FLOOR + z, WALL + 2, w, h)

    for x, y in FEET:
        body -= cyl(x, y, -0.1, FOOT_D, FOOT_DEPTH + 0.1)
    return body


def lid():
    plate = rounded_rect(WIDTH, LENGTH, CORNER_R).extrude(LID)
    o = WALL + LIP_GAP
    lip_out = rounded_rect(WIDTH - 2 * o, LENGTH - 2 * o, CORNER_R - o).translate([o, o])
    i = o + LIP_W
    lip_in = rounded_rect(WIDTH - 2 * i, LENGTH - 2 * i, CORNER_R - i).translate([i, i])
    lip = (lip_out - lip_in).extrude(LIP_H).translate([0, 0, LID])
    for x, y in LID_POSTS:
        lip -= cyl(x, y, LID - 0.1, LID_POST_D + 1.0, LIP_H + 1)
    body = plate + lip
    for x, y in LID_POSTS:
        body -= cyl(x, y, -1, LID_HOLE_D, LID + 2)
        # Countersink on the outer face (z = 0), which goes against the tablet.
        sink = Manifold.cylinder(1.7, LID_HEAD_D / 2, LID_HOLE_D / 2).translate([x, y, -0.01])
        body -= sink
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


def save(m, path):
    mesh = m.to_mesh()
    verts = np.asarray(mesh.vert_properties)[:, :3]
    trimesh.Trimesh(verts, np.asarray(mesh.tri_verts)).export(path)


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
        if sx < 15 and sy < 15:  # too small to hold its own label
            ax.annotate(label, (x + sx, y + sy / 2), (x + sx + 14, y + sy / 2 + 6), fontsize=7,
                        va="center", arrowprops=dict(arrowstyle="-", color="#444"))
            continue
        ax.text(x + sx / 2, y + sy / 2, label, ha="center", va="center", fontsize=6.5,
                color="white", weight="bold", rotation=90 if sy > 2.5 * sx else 0)
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
    ax.text(WIDTH / 2, LENGTH / 2 + 20, "empty\n(room for wiring)", ha="center", color="#aaa")
    ax.text(WIDTH / 2, -30, "BOTTOM EDGE (tablet port and buttons)", ha="center", fontsize=9)
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
    out = os.path.join(here, "stl")
    os.makedirs(out, exist_ok=True)

    t, l = tray(), lid()
    save(t, os.path.join(out, "tray.stl"))
    save(l, os.path.join(out, "lid.stl"))
    for i, (name, rect, posts, _) in enumerate(straps()):
        save(strap_part(rect, posts), os.path.join(out, f"strap_{i + 1}_{name}.stl"))
    if args.split:
        for part, m in (("tray", t), ("lid", l)):
            a, b = m.split_by_plane([0, 1, 0], LENGTH / 2)
            save(b, os.path.join(out, f"{part}_bottom_half.stl"))
            save(a, os.path.join(out, f"{part}_top_half.stl"))
        save(splice(), os.path.join(out, "splice_plate.stl"))
    layout_png(os.path.join(here, "layout.png"))
    print(f"tray {t.volume() / 1000:.0f} cm3, lid {l.volume() / 1000:.0f} cm3, height "
          f"{FLOOR + INNER_H + LID:g} mm")


if __name__ == "__main__":
    main()
