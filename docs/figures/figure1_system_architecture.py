import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
from matplotlib import font_manager as fm

for f in ["LiberationSerif-Regular.ttf", "LiberationSerif-Bold.ttf", "LiberationSerif-Italic.ttf"]:
    fm.fontManager.addfont("/usr/share/fonts/truetype/liberation/" + f)
plt.rcParams["font.family"] = "Liberation Serif"

FW, FH = 10.3, 4.9                     # inches; axes units are inches
fig = plt.figure(figsize=(FW, FH))
ax = fig.add_axes([0, 0, 1, 1]); ax.set_xlim(0, FW); ax.set_ylim(0, FH); ax.axis("off")

BW, BH, GAP = 1.85, 1.45, 0.9
X = [0.1, 0.1 + BW + GAP, 0.1 + 2 * (BW + GAP)]
R1, R2 = 3.1, 0.55                    # bottoms of the two rows

def box(x, y, title, body, w=BW, h=BH, dash=False):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.08",
                                fc="white", ec="black", lw=1.3))
    ax.text(x + w / 2, y + h - 0.2, title, ha="center", va="center", fontsize=12, weight="bold")
    ax.plot([x + 0.12, x + w - 0.12], [y + h - 0.38] * 2, color="black", lw=0.6)
    ax.text(x + w / 2, y + (h - 0.38) / 2, body, ha="center", va="center", fontsize=10,
            linespacing=1.3)

def arrow(p0, p1, dashed=False):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=13, lw=1.2,
                                 color="black", shrinkA=0, shrinkB=0,
                                 linestyle=(0, (4, 3)) if dashed else "-"))

def label(x, y, text, **kw):
    ax.text(x, y, text, ha="center", va="center", fontsize=9.5, style="italic",
            linespacing=1.15, **kw)

# Row 1: stylus, tablet, relay. Row 2: cloud, app.
box(X[0], R1, "Stylus", "Modified EMR stylus\nwith pencil-lead nib\nand two buttons")
box(X[1], R1, "Digitizer Tablet", "Lumispark T605\nunder the notebook:\nposition, pressure,\nbuttons")
box(X[2], R1, "ESP32-S3 Relay", "USB host for\nthe tablet\nOffline buffer\n(70,000 reports)")
box(X[2], R2, "Mobile App", "Android (Flutter)\nLive ink, notebooks,\nhandwriting search,\nlocal storage")
box(X[1], R2, "Cloud", "Supabase\nBackup and sync\nwhen signed in")

# Power, beside the relay, both inside the cardboard case.
PX, PW = X[2] + BW + GAP, 1.75
box(PX, R1, "Relay Power", "3.7 V LiPo\nTP4056 charger\nOn/off switch\nMT3608 boost (5 V)", w=PW)
ax.add_patch(FancyBboxPatch((X[2] - 0.12, R1 - 0.32), PX + PW - X[2] + 0.24, BH + 0.5,
             boxstyle="round,pad=0.02,rounding_size=0.12", fc="none", ec="black", lw=1.0,
             linestyle=(0, (1, 2))))
ax.text(X[2] + (PX + PW - X[2]) / 2, R1 - 0.18, "Cardboard case on the back of the tablet",
        ha="center", va="center", fontsize=9.5, style="italic")

mid1, mid2 = R1 + BH / 2, R2 + BH / 2
arrow((X[0] + BW, mid1), (X[1], mid1)); label(X[0] + BW + GAP / 2, mid1 + 0.3, "Writes on\npaper")
arrow((X[1] + BW, mid1), (X[2], mid1)); label(X[1] + BW + GAP / 2, mid1 + 0.3, "USB data\nand 5 V")
arrow((PX, mid1), (X[2] + BW, mid1)); label(X[2] + BW + GAP / 2, mid1 + 0.22, "5 V")
cx = X[2] + BW / 2
arrow((cx, R1 - 0.34), (cx, R2 + BH)); label(cx + 0.55, (R1 - 0.34 + R2 + BH) / 2, "Bluetooth LE")
arrow((X[2], mid2), (X[1] + BW, mid2)); label(X[1] + BW + GAP / 2, mid2 + 0.22, "Internet")

# Direct option: tablet straight to the app with a USB OTG cable.
tx = X[1] + BW * 0.78
ax.plot([tx, tx, X[2] + 0.35], [R1, R2 + BH + 0.32, R2 + BH + 0.32], color="black", lw=1.1,
        linestyle=(0, (4, 3)))
arrow((X[2] + 0.35, R2 + BH + 0.32), (X[2] + 0.35, R2 + BH), dashed=True)
label(X[1] + 0.62, R2 + BH + 0.6, "USB OTG cable\n(direct, no relay)")

fig.savefig("figure1_system_architecture.png", dpi=300, facecolor="white")
