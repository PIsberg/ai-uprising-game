"""Build the GUNSLINGER's model from primitives: assets/models/robots/gunslinger_automaton.glb.

    blender --background --python tools/blender/build_gunslinger.py -- <preview.png> [more previews...]

The model is original to this game (no third-party mesh or texture), so it carries
no licence terms. It replaced a Sketchfab Standard download whose terms forbid
keeping it as a stand-alone file in a public repository (#517).

A brass automaton duelist: a flat-brimmed hat over a riveted face with one glowing
monocle, a boiler chest with a lit furnace grate and a pressure gauge, a gun belt,
a duster's tails of dark leather plate behind, piston legs with cog knees and
spurred boots. Its right forearm ends in a revolver: drum at the wrist, a long
octagonal barrel. Its left ends in a three-fingered claw.

What scripts/enemies/enemy_gunslinger.gd and its probes rely on:
  * `Forearms`      both forearms in ONE mesh, hanging straight down from the elbows;
                    the script splits it at x = 0. On the right (x > 0) the highest
                    band is the elbow it swings about and the farthest vertices from
                    it are the barrel's end, where every slug leaves (gunslinger_arm_probe).
  * `LegL`, `LegR`  one mesh per leg; each leg's highest band is its hip (biped_gait_probe).
  * `Body`          everything else, upper arms included; it never moves.
The model is 1.9 m tall and recentred (primkit.centre), so RobotModel's fit
(fit_height 1.9, fit_yaw 0) is a scale of 1 and no shift.
"""
import bpy, sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import primkit as K
from primkit import box, cyl, ball, beam, rod
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath("assets/models/robots/gunslinger_automaton.glb")
HEIGHT = 1.9

K.reset()
BRASS = K.mat("GslBrass", (0.74, 0.52, 0.2), 1.0, 0.33)
COPPER = K.mat("GslCopper", (0.62, 0.3, 0.16), 1.0, 0.4)
IRON = K.mat("GslIron", (0.075, 0.07, 0.065), 0.8, 0.5)
LEATHER = K.mat("GslLeather", (0.055, 0.03, 0.018), 0.1, 0.8)
GLOW = K.mat("GslGlow", (1.0, 0.45, 0.1), 0.1, 0.3, (1.0, 0.38, 0.06), 2.5)

BODY, LEGL, LEGR, ARMS = [], [], [], []


def cog(group, loc, r, width, m, axis='X', teeth=10):
    """A gear: a disc with square teeth round its rim."""
    cyl(group, loc, r, width, m, axis=axis, verts=16)
    loc = Vector(loc)
    for i in range(teeth):
        a = math.tau * i / teeth
        if axis == 'X':
            off = Vector((0, math.cos(a), math.sin(a))) * (r + 0.008)
            box(group, loc + off, (width, 0.018, 0.018), m, rot=(math.degrees(a), 0, 0), bevel=0.0)
        else:
            off = Vector((math.cos(a), 0, math.sin(a))) * (r + 0.008)
            box(group, loc + off, (0.018, width, 0.018), m, rot=(0, -math.degrees(a), 0), bevel=0.0)


# ---------------------------------------------------------------- torso
HIP_Z = 0.92
box(BODY, (0, 0, 0.99), (0.3, 0.19, 0.12), IRON, bevel=0.025)                # pelvis
cyl(BODY, (0, 0, 1.07), 0.13, 0.09, IRON, verts=16)                           # waist
cyl(BODY, (0, 0, 1.03), 0.165, 0.045, LEATHER, verts=20)                      # gun belt
cyl(BODY, (0, 0, 1.03), 0.168, 0.012, BRASS, verts=20)                        # its brass seam
box(BODY, (0, 0.165, 1.03), (0.07, 0.015, 0.055), BRASS, bevel=0.005)         # buckle
for i in range(7):                                                             # cartridge loops
    a = math.radians(-60 + i * 20)
    cyl(BODY, (math.sin(a) * 0.17, math.cos(a) * 0.17 if i != 3 else -0.17, 1.045), 0.008, 0.05, BRASS, verts=6)
box(BODY, (-0.19, 0.03, 0.95), (0.05, 0.1, 0.15), LEATHER, rot=(0, 8, 0))      # empty holster, left hip
cyl(BODY, (0, 0, 1.3), 0.18, 0.36, BRASS, verts=24, bevel=0.01)               # boiler
for z in (1.14, 1.46):
    cyl(BODY, (0, 0, z), 0.188, 0.025, COPPER, verts=24)                      # boiler hoops
box(BODY, (0, 0.165, 1.27), (0.15, 0.05, 0.15), IRON, bevel=0.012)            # furnace door
for i in range(4):                                                             # its grate, lit
    box(BODY, (-0.045 + i * 0.03, 0.192, 1.27), (0.016, 0.006, 0.11), GLOW, bevel=0.0)
cyl(BODY, (0.11, 0.155, 1.4), 0.04, 0.03, BRASS, axis='Y', verts=16)          # pressure gauge
cyl(BODY, (0.11, 0.172, 1.4), 0.032, 0.006, GLOW, axis='Y', verts=16)         # its face
box(BODY, (0.11, 0.177, 1.405), (0.004, 0.003, 0.028), IRON, rot=(0, 35, 0), bevel=0.0)   # needle
for sx in (-1, 1):                                                             # rivet lines
    for i in range(5):
        ball(BODY, (sx * 0.08, 0.17, 1.17 + i * 0.05), 0.008, COPPER, segs=6)
box(BODY, (0, 0.0, 1.5), (0.4, 0.2, 0.06), IRON, bevel=0.02)                  # shoulder yoke
# Duster tails: leather plates hanging from the waist behind, split up the middle.
for sx in (-1, 1):
    beam(BODY, (sx * 0.1, -0.17, 1.12), (sx * 0.15, -0.27, 0.5), 0.17, 0.016, LEATHER, bevel=0.0)
    beam(BODY, (sx * 0.1, -0.165, 1.1), (sx * 0.15, -0.262, 0.54), 0.02, 0.02, BRASS, bevel=0.0)   # its brass edge
# Back: a smokestack off the left shoulder blade, and copper pipes round to the yoke.
cyl(BODY, (-0.11, -0.19, 1.5), 0.04, 0.42, IRON, verts=12)
cyl(BODY, (-0.11, -0.19, 1.725), 0.055, 0.04, COPPER, verts=12)
cyl(BODY, (0.0, -0.175, 1.3), 0.11, 0.3, COPPER, verts=16)                   # back tank
for sx in (-1, 1):
    rod(BODY, (sx * 0.08, -0.2, 1.42), (sx * 0.18, -0.05, 1.53), 0.014, COPPER, verts=6)

# Pauldrons: domed brass caps over the shoulder joints, a cog on each.
for sx in (-1, 1):
    ball(BODY, (sx * 0.27, 0, 1.5), 0.1, BRASS, segs=16, scale=(1.0, 1.0, 0.7))
    box(BODY, (sx * 0.27, 0, 1.46), (0.22, 0.2, 0.03), IRON, bevel=0.01)
    cog(BODY, (sx * 0.36, 0, 1.44), 0.045, 0.02, COPPER)

# ---------------------------------------------------------------- head
cyl(BODY, (0, 0, 1.57), 0.05, 0.09, IRON, verts=12)                           # neck
cyl(BODY, (0, 0.0, 1.66), 0.1, 0.17, BRASS, verts=20, bevel=0.01)             # face drum
box(BODY, (0, 0.085, 1.6), (0.12, 0.04, 0.045), IRON, bevel=0.008)            # mouth grille
for i in range(5):
    box(BODY, (-0.04 + i * 0.02, 0.105, 1.6), (0.006, 0.006, 0.035), BRASS, bevel=0.0)
cyl(BODY, (0.04, 0.09, 1.675), 0.038, 0.03, BRASS, axis='Y', verts=16)        # monocle rim
cyl(BODY, (0.04, 0.104, 1.675), 0.03, 0.006, GLOW, axis='Y', verts=16)        # monocle
cyl(BODY, (-0.045, 0.094, 1.675), 0.016, 0.02, IRON, axis='Y', verts=10)      # the other eye, dark
rod(BODY, (0.07, 0.09, 1.64), (0.1, 0.06, 1.52), 0.004, BRASS, verts=4)       # monocle chain
# The hat: a flat brim, a crown, a copper band.
cyl(BODY, (0, 0, 1.765), 0.24, 0.018, LEATHER, verts=28)
cyl(BODY, (0, 0, 1.83), 0.115, 0.13, LEATHER, verts=20, r2=0.105)
cyl(BODY, (0, 0, 1.785), 0.118, 0.025, COPPER, verts=20)
box(BODY, (0, 0, HEIGHT - 0.01), (0.15, 0.06, 0.02), LEATHER, bevel=0.01)     # the crown's pinch, its top

# ---------------------------------------------------------------- arms
ELBOW_X = 0.33
ELBOW_Z = 1.1
for sx in (-1, 1):   # upper arms (Body): shoulder to just above the elbow
    beam(BODY, (sx * 0.29, 0, 1.45), (sx * ELBOW_X, 0, ELBOW_Z + 0.05), 0.06, 0.065, IRON)
    rod(BODY, (sx * 0.31, 0.05, 1.4), (sx * ELBOW_X, 0.04, ELBOW_Z + 0.08), 0.012, BRASS, verts=6)   # piston
# Forearms (one mesh): each hangs straight down from its elbow joint, whose top is the forearm's top.
for sx in (-1, 1):
    ball(ARMS, (sx * ELBOW_X, 0, ELBOW_Z), 0.045, BRASS, segs=12)
    cyl(ARMS, (sx * ELBOW_X, 0, ELBOW_Z - 0.13), 0.042, 0.2, IRON, verts=12, r2=0.036)
    cyl(ARMS, (sx * ELBOW_X, 0, ELBOW_Z - 0.09), 0.048, 0.03, COPPER, verts=12)
# Right: the revolver. Drum at the wrist, frame, an octagonal barrel down to the muzzle.
RX = ELBOW_X
box(ARMS, (RX, 0, 0.86), (0.06, 0.08, 0.08), BRASS, bevel=0.01)                # frame
cyl(ARMS, (RX, 0, 0.8), 0.058, 0.07, IRON, verts=6, bevel=0.006)              # drum (six flutes)
cyl(ARMS, (RX, 0, 0.8), 0.06, 0.02, BRASS, verts=12)
cyl(ARMS, (RX, 0, 0.66), 0.024, 0.22, IRON, verts=8)                          # barrel
cyl(ARMS, (RX, 0, 0.66), 0.03, 0.02, BRASS, verts=8)
box(ARMS, (RX, 0.022, 0.58), (0.008, 0.012, 0.03), BRASS, bevel=0.0)          # front sight
cyl(ARMS, (RX, 0, 0.55), 0.03, 0.02, BRASS, verts=8)                          # muzzle ring: the far end
box(ARMS, (RX, -0.05, 0.88), (0.02, 0.03, 0.06), BRASS, rot=(-30, 0, 0), bevel=0.0)  # hammer
# Left: a three-fingered claw.
LX = -ELBOW_X
box(ARMS, (LX, 0, 0.83), (0.07, 0.07, 0.06), BRASS, bevel=0.01)
for i, (dx, dy) in enumerate([(0.0, 0.035), (-0.03, -0.02), (0.03, -0.02)]):
    rod(ARMS, (LX + dx, dy, 0.8), (LX + dx * 1.4, dy * 1.5, 0.72), 0.01, IRON, verts=6)
    rod(ARMS, (LX + dx * 1.4, dy * 1.5, 0.72), (LX + dx * 1.1, dy * 1.1, 0.66), 0.008, IRON, verts=6, r2=0.003)

# ---------------------------------------------------------------- legs
def leg(group, sx):
    hip = Vector((sx * 0.12, 0, HIP_Z))
    knee = Vector((sx * 0.125, 0.03, 0.52))
    ankle = Vector((sx * 0.125, -0.01, 0.12))
    ball(group, hip, 0.06, IRON)                                           # hip: the leg's top
    beam(group, hip, knee, 0.085, 0.09, IRON, bevel=0.015)                 # thigh
    cyl(group, hip.lerp(knee, 0.45), 0.055, 0.12, BRASS, verts=14)         # thigh collar
    cog(group, knee + Vector((sx * 0.055, 0, 0)), 0.05, 0.02, COPPER)      # knee cog, outer face
    ball(group, knee, 0.05, IRON)
    beam(group, knee, ankle, 0.07, 0.075, IRON, bevel=0.012)               # shin
    rod(group, knee + Vector((0, 0.06, -0.05)), ankle + Vector((0, 0.055, 0.12)), 0.014, BRASS, verts=6)  # piston
    # Boot: a spat over the ankle, a toe, a heel and a spur.
    cyl(group, (ankle.x, ankle.y, ankle.z), 0.06, 0.12, LEATHER, verts=12)
    box(group, (ankle.x, 0.06, 0.035), (0.1, 0.22, 0.07), LEATHER, bevel=0.02)
    box(group, (ankle.x, -0.06, 0.03), (0.09, 0.05, 0.06), IRON, bevel=0.01)
    rod(group, (ankle.x, -0.085, 0.05), (ankle.x, -0.12, 0.05), 0.006, BRASS, verts=4)
    cyl(group, (ankle.x, -0.13, 0.05), 0.018, 0.006, BRASS, axis='X', verts=8)   # the spur's rowel


leg(LEGL, -1)
leg(LEGR, 1)

# ---------------------------------------------------------------- join, centre, export
body = K.join(BODY, "Body")
legl = K.join(LEGL, "LegL")
legr = K.join(LEGR, "LegR")
arms = K.join(ARMS, "Forearms")
ALL = [body, legl, legr, arms]
SHIFT = K.centre(ALL, HEIGHT)

right = [arms.matrix_world @ v.co for v in arms.data.vertices if (arms.matrix_world @ v.co).x > 0]
top = max(w.z for w in right)
elbow = sum([w for w in right if w.z > top - 0.04], Vector()) / len([w for w in right if w.z > top - 0.04])
far = max((w - elbow).length for w in right)
tip = sum([w for w in right if (w - elbow).length > far - 0.03], Vector()) / len([w for w in right if (w - elbow).length > far - 0.03])
print("GUN-ARM elbow %s tip %s (%.3f m)" % (tuple(round(c, 3) for c in K.godot(elbow)), tuple(round(c, 3) for c in K.godot(tip)), far))
for name, o in (("LegL", legl), ("LegR", legr)):
    print("HIP %s %s" % (name, tuple(round(c, 3) for c in K.top_band(o))))
print("MONOCLE %s" % (tuple(round(c, 3) for c in K.godot(SHIFT @ Vector((0.04, 0.104, 1.675)))),))

K.export(ALL, OUT)
K.previews(ALL, ARGS)
