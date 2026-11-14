"""Build the REAPER's model from primitives: assets/models/robots/reaper_droid.glb.

    blender --background --python tools/blender/build_reaper.py -- <preview.png> [more previews...]

The model is original to this game (no third-party mesh or texture), so it carries
no licence terms. It replaced a Sketchfab Standard download whose terms forbid
keeping it as a stand-alone file in a public repository (#517).

A gaunt sprinter in gunmetal: a hooded skull face with two red eye slits, a ribbed
chest round a red core, a bare spine at the waist, long digitigrade-looking legs
on clawed feet, and a heavy rifle held at the right hip in both hands. Tattered
cloth strips hang from its back, raked as if it has been running.

What scripts/enemies/enemy_reaper.gd and its probes rely on:
  * `LegL`, `LegR`  one mesh per leg; each leg's highest band is its hip, which is
                    where BipedGait swings it from (biped_gait_probe).
  * `Rifle`         the whole gun; its front-most vertices are the muzzle brake, where
                    every round leaves (RIFLE_TIP, reaper_rifle_probe).
  * `Body`          everything else, arms and hands included; it never moves.
The model is 1.8 m tall and recentred (primkit.centre), so RobotModel's fit
(fit_height 1.8, fit_yaw 0) is a scale of 1 and no shift, and the numbers printed
at the end are the body-frame numbers the script uses.
"""
import bpy, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import primkit as K
from primkit import box, cyl, ball, beam, rod
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath("assets/models/robots/reaper_droid.glb")
HEIGHT = 1.8

K.reset()
GUN = K.mat("ReaGunmetal", (0.12, 0.125, 0.14), 0.75, 0.42)    # main armour
PLATE = K.mat("ReaPlate", (0.27, 0.28, 0.31), 0.7, 0.38)       # lighter plates
BONE = K.mat("ReaBone", (0.66, 0.63, 0.56), 0.25, 0.5)         # the skull face
DARK = K.mat("ReaDark", (0.035, 0.035, 0.045), 0.6, 0.55)      # joints, recesses
CLOTH = K.mat("ReaCloth", (0.07, 0.012, 0.01), 0.0, 0.95)       # the tattered strips
RED = K.mat("ReaRed", (1.0, 0.12, 0.06), 0.1, 0.3, (1.0, 0.1, 0.05), 3.0)  # eyes, core, sight

BODY, LEGL, LEGR, RIFLE = [], [], [], []

# ---------------------------------------------------------------- torso
HIP_Z = 0.9
box(BODY, (0, 0, 0.95), (0.3, 0.17, 0.12), GUN, bevel=0.02)                 # pelvis
box(BODY, (0, 0.07, 0.92), (0.14, 0.05, 0.14), PLATE, rot=(-12, 0, 0))       # codpiece plate
for i in range(4):                                                           # bare spine
    cyl(BODY, (0, -0.02, 1.03 + i * 0.045), 0.045 - i * 0.003, 0.03, DARK, verts=10)
cyl(BODY, (0, -0.02, 1.08), 0.022, 0.2, PLATE, verts=8)                      # the spine's rod
box(BODY, (0, -0.01, 1.32), (0.34, 0.2, 0.22), GUN, bevel=0.03)              # ribcage
box(BODY, (0, 0.02, 1.43), (0.42, 0.22, 0.08), GUN, bevel=0.025)             # collar yoke
box(BODY, (0, 0.105, 1.3), (0.06, 0.03, 0.24), PLATE)                        # sternum
for sx in (-1, 1):
    for i in range(3):                                                       # ribs
        box(BODY, (sx * 0.1, 0.1, 1.24 + i * 0.06), (0.11, 0.025, 0.028), PLATE, rot=(0, sx * -14, 0))
cyl(BODY, (0, 0.1, 1.33), 0.032, 0.03, RED, axis='Y', verts=12)              # core between the ribs
box(BODY, (0, -0.1, 1.33), (0.22, 0.04, 0.2), DARK)                          # back plate under the strips
# Shoulders: angular pauldrons raked down and out.
for sx in (-1, 1):
    box(BODY, (sx * 0.25, 0.0, 1.45), (0.14, 0.17, 0.08), PLATE, rot=(0, sx * 22, 0), bevel=0.02)
    box(BODY, (sx * 0.29, 0.0, 1.41), (0.06, 0.15, 0.1), GUN, rot=(0, sx * 22, 0))
    ball(BODY, (sx * 0.24, 0.0, 1.39), 0.045, DARK)

# ---------------------------------------------------------------- head
cyl(BODY, (0, 0.0, 1.53), 0.035, 0.1, DARK, verts=10)                        # neck
box(BODY, (0, 0.02, 1.65), (0.13, 0.15, 0.19), BONE, bevel=0.035)            # skull
box(BODY, (0, 0.085, 1.56), (0.1, 0.06, 0.06), BONE, rot=(-15, 0, 0), bevel=0.015)   # jaw
for i in range(4):                                                           # jaw slats
    box(BODY, (-0.03 + i * 0.02, 0.117, 1.56), (0.008, 0.012, 0.045), DARK, bevel=0.0)
for sx in (-1, 1):
    box(BODY, (sx * 0.033, 0.095, 1.665), (0.045, 0.012, 0.014), RED, rot=(0, sx * 12, 0), bevel=0.0)  # eye slits
    box(BODY, (sx * 0.033, 0.09, 1.665), (0.055, 0.012, 0.03), DARK, rot=(0, sx * 12, 0), bevel=0.0)
# The hood: a shell over the crown and back of the skull, its brow overhanging the eyes.
box(BODY, (0, -0.005, 1.74), (0.17, 0.19, 0.05), GUN, bevel=0.02)
box(BODY, (0, -0.075, 1.65), (0.17, 0.05, 0.2), GUN, bevel=0.02)
for sx in (-1, 1):
    box(BODY, (sx * 0.078, 0.0, 1.66), (0.025, 0.17, 0.17), GUN, bevel=0.01)
box(BODY, (0, 0.088, 1.71), (0.17, 0.04, 0.03), GUN, rot=(25, 0, 0), bevel=0.01)     # brow
rod(BODY, (0.06, -0.08, 1.74), (0.09, -0.15, HEIGHT), 0.008, DARK, verts=6, r2=0.003)  # antenna, the tallest point

# Tattered strips off the shoulder blades, raked back.
for i, (sx, length, rake) in enumerate([(-0.15, 0.62, 0.32), (-0.08, 0.72, 0.38), (0.0, 0.66, 0.42),
                                         (0.08, 0.74, 0.37), (0.15, 0.58, 0.31)]):
    top = Vector((sx, -0.13, 1.44))
    bot = Vector((sx * 1.25, -0.13 - rake, 1.44 - length))
    beam(BODY, top, bot, 0.065, 0.012, CLOTH, bevel=0.0)
    beam(BODY, bot + (top - bot) * 0.12 + Vector((0.02, 0, 0)), bot + Vector((0.025, -0.01, -0.03)), 0.03, 0.012, CLOTH, bevel=0.0)

# ---------------------------------------------------------------- rifle
BORE_Z = 1.0
BORE_X = 0.2
MUZZLE_Y = 0.62
box(RIFLE, (BORE_X, -0.2, BORE_Z - 0.01), (0.05, 0.2, 0.08), GUN, rot=(-6, 0, 0))      # stock
box(RIFLE, (BORE_X, -0.31, BORE_Z - 0.02), (0.06, 0.03, 0.12), DARK)                    # butt pad
box(RIFLE, (BORE_X, 0.04, BORE_Z), (0.075, 0.3, 0.11), GUN, bevel=0.015)               # receiver
box(RIFLE, (BORE_X + 0.04, 0.02, BORE_Z + 0.01), (0.008, 0.12, 0.04), DARK, bevel=0.0)  # ejection port
box(RIFLE, (BORE_X, 0.06, BORE_Z - 0.1), (0.045, 0.07, 0.14), DARK, rot=(-14, 0, 0))   # magazine
box(RIFLE, (BORE_X, -0.06, BORE_Z - 0.08), (0.035, 0.04, 0.09), DARK, rot=(18, 0, 0))  # pistol grip
box(RIFLE, (BORE_X, 0.3, BORE_Z), (0.07, 0.24, 0.085), PLATE, bevel=0.012)             # barrel shroud
for i in range(5):                                                                      # shroud vents
    for sx in (-1, 1):
        box(RIFLE, (BORE_X + sx * 0.036, 0.22 + i * 0.04, BORE_Z), (0.006, 0.022, 0.03), DARK, bevel=0.0)
cyl(RIFLE, (BORE_X, 0.5, BORE_Z), 0.018, 0.16, DARK, axis='Y', verts=10)               # barrel
cyl(RIFLE, (BORE_X, MUZZLE_Y - 0.035, BORE_Z), 0.03, 0.07, GUN, axis='Y', verts=10)    # muzzle brake
for dy in (-0.05, -0.025):
    box(RIFLE, (BORE_X, MUZZLE_Y + dy, BORE_Z), (0.075, 0.01, 0.02), DARK, bevel=0.0)  # brake baffles
box(RIFLE, (BORE_X, 0.32, BORE_Z - 0.065), (0.035, 0.05, 0.06), DARK, rot=(10, 0, 0))   # foregrip
cyl(RIFLE, (BORE_X, 0.02, BORE_Z + 0.085), 0.022, 0.15, DARK, axis='Y', verts=10)     # sight tube
cyl(RIFLE, (BORE_X, 0.098, BORE_Z + 0.085), 0.016, 0.006, RED, axis='Y', verts=10)    # its lens
for dy in (-0.03, 0.06):
    box(RIFLE, (BORE_X, dy, BORE_Z + 0.06), (0.015, 0.015, 0.03), DARK, bevel=0.0)    # sight mounts

# ---------------------------------------------------------------- arms (Body): both hands on the rifle
def arm(shoulder, elbow, hand):
    shoulder = Vector(shoulder); elbow = Vector(elbow); hand = Vector(hand)
    beam(BODY, shoulder, elbow, 0.045, 0.05, GUN)
    beam(BODY, shoulder.lerp(elbow, 0.2), shoulder.lerp(elbow, 0.7), 0.06, 0.035, PLATE)
    ball(BODY, elbow, 0.035, DARK)
    beam(BODY, elbow, hand, 0.04, 0.045, GUN)
    beam(BODY, elbow.lerp(hand, 0.25), elbow.lerp(hand, 0.8), 0.055, 0.03, PLATE)
    box(BODY, hand, (0.05, 0.055, 0.05), DARK, bevel=0.01)


arm((0.25, 0.0, 1.39), (0.29, -0.07, 1.14), (BORE_X + 0.01, -0.06, BORE_Z - 0.07))      # right: the grip
arm((-0.25, 0.0, 1.39), (-0.22, 0.12, 1.15), (BORE_X - 0.01, 0.32, BORE_Z - 0.1))       # left: the foregrip

# ---------------------------------------------------------------- legs
def leg(group, sx):
    hip = Vector((sx * 0.12, 0.0, HIP_Z))
    knee = Vector((sx * 0.13, 0.09, 0.52))
    ankle = Vector((sx * 0.13, -0.07, 0.14))
    ball(group, hip, 0.055, DARK)                                  # hip joint: the leg's top
    beam(group, hip, knee, 0.075, 0.085, GUN, bevel=0.02)          # thigh
    beam(group, hip.lerp(knee, 0.15) + Vector((sx * 0.03, 0.02, 0)), hip.lerp(knee, 0.75) + Vector((sx * 0.03, 0.03, 0)),
         0.04, 0.09, PLATE, bevel=0.012)                           # thigh plate, outer face
    ball(group, knee, 0.045, DARK)
    box(group, knee + Vector((0, 0.04, 0.01)), (0.07, 0.04, 0.08), PLATE, rot=(-20, 0, 0))   # knee cap
    beam(group, knee, ankle, 0.055, 0.065, GUN, bevel=0.015)       # shin
    rod(group, knee + Vector((0, -0.05, -0.04)), ankle + Vector((0, -0.04, 0.12)), 0.012, DARK, verts=6)  # tendon
    ball(group, ankle, 0.035, DARK)
    # Clawed foot: two toes forward, a heel spur back.
    for tx in (-0.03, 0.03):
        beam(group, ankle + Vector((tx, 0.01, -0.04)), Vector((ankle.x + tx * 1.5, 0.15, 0.025)), 0.035, 0.04, PLATE, bevel=0.008)
        rod(group, (ankle.x + tx * 1.5, 0.15, 0.025), (ankle.x + tx * 1.6, 0.2, 0.0), 0.016, DARK, verts=6, r2=0.003)
    beam(group, ankle + Vector((0, -0.01, -0.05)), Vector((ankle.x, -0.15, 0.0)), 0.03, 0.03, DARK, bevel=0.005)


leg(LEGL, -1)
leg(LEGR, 1)

# ---------------------------------------------------------------- join, centre, export
body = K.join(BODY, "Body")
legl = K.join(LEGL, "LegL")
legr = K.join(LEGR, "LegR")
rifle = K.join(RIFLE, "Rifle")
ALL = [body, legl, legr, rifle]
SHIFT = K.centre(ALL, HEIGHT)

rmn, rmx = K.bounds([rifle])
# The brake's front face: the rifle's vertices within 1 cm of its front-most point.
brake = [rifle.matrix_world @ v.co for v in rifle.data.vertices if (rifle.matrix_world @ v.co).y > rmx.y - 0.01]
bc = sum(brake, Vector()) / len(brake)
print("RIFLE_TIP (front of the brake, body frame) %s" % (tuple(round(c, 3) for c in K.godot(bc)),))
for name, o in (("LegL", legl), ("LegR", legr)):
    print("HIP %s %s" % (name, tuple(round(c, 3) for c in K.top_band(o))))
print("EYES (between the slits) %s" % (tuple(round(c, 3) for c in K.godot(SHIFT @ Vector((0, 0.1, 1.665)))),))

K.export(ALL, OUT)
K.previews(ALL, ARGS)
