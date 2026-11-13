"""Build the HOWITZER's model from primitives: assets/models/robots/howitzer_walker.glb.

    blender --background --python tools/blender/build_howitzer.py -- <preview.png> [more previews...]

The model is original to this game (no third-party mesh or texture), so it carries
no licence terms. It replaced a CC-BY-NC download that a paid build may not ship (#406).

What scripts/enemies/enemy_howitzer.gd and its probes rely on:
  * `Gun`   an empty at the origin whose one child mesh (`GunBarrel`) is the whole laying
            mass: tube, sleeve, breech. It pitches about the trunnion and slides on recoil.
  * `Legs`  all four legs in ONE mesh; the script cuts it left/right of x = 0 and
            front/back of LEGS_SPLIT_Z. Each leg's highest 8 cm is its hip cap, which is
            where the script finds the hip it swings the leg about.
  * `Hull`  everything else.
Blender axes: +Y is the front (Godot -Z after export), Z up, metres. The model is built
4.3 m tall and symmetric in x and y, so RobotModel's fit (fit_height 4.3) is a scale of 1
and no shift, and every number below is also the Godot body-frame number (z = -y).
The script prints the measured ones at the end; they are pinned by howitzer_model_probe.
"""
import bpy, sys, os, math
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath("assets/models/robots/howitzer_walker.glb")

bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, col, metal=0.8, rough=0.45, emis=None, ee=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    b.inputs['Base Color'].default_value = (col[0], col[1], col[2], 1)
    b.inputs['Metallic'].default_value = metal
    b.inputs['Roughness'].default_value = rough
    if emis:
        b.inputs['Emission Color'].default_value = (emis[0], emis[1], emis[2], 1)
        b.inputs['Emission Strength'].default_value = ee
    m.diffuse_color = (col[0], col[1], col[2], 1)  # workbench preview colour
    return m


ARMOR = mat("HowArmor", (0.20, 0.23, 0.17), 0.55, 0.5)      # drab plate
PLATE = mat("HowPlate", (0.25, 0.27, 0.2), 0.5, 0.55)      # lighter applique plate
DARK = mat("HowDark", (0.06, 0.065, 0.075), 0.75, 0.5)      # joints, recesses
STEEL = mat("HowSteel", (0.42, 0.43, 0.45), 0.95, 0.28)     # barrel, pistons
HAZARD = mat("HowHazard", (0.85, 0.5, 0.06), 0.3, 0.5)      # painted warning bands
AMBER = mat("HowAmber", (1.0, 0.5, 0.08), 0.2, 0.3, (1.0, 0.45, 0.06), 5.0)  # optics, vents

HULL, GUN, LEGS = [], [], []


def _finish(o, m, group, bevel):
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if bevel > 0.0:
        mod = o.modifiers.new("b", 'BEVEL')
        mod.width = bevel; mod.segments = 2; mod.limit_method = 'ANGLE'
        mod.angle_limit = math.radians(40)
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.materials.append(m)
    group.append(o)
    return o


def box(group, loc, size, m, rot=(0, 0, 0), bevel=0.025):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.active_object
    o.scale = size
    o.rotation_euler = [math.radians(a) for a in rot]
    return _finish(o, m, group, bevel)


def cyl(group, loc, r, depth, m, axis='Z', verts=16, r2=None, bevel=0.015, rot=None):
    """A cylinder (or a cone frustum when r2 is given: r at the -axis end, r2 at the + end)."""
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, vertices=verts)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=depth, location=loc, vertices=verts)
    o = bpy.context.active_object
    if rot is not None:
        o.rotation_euler = [math.radians(a) for a in rot]
    elif axis == 'Y':
        o.rotation_euler = (math.radians(-90), 0, 0)   # +Z end -> +Y
    elif axis == 'X':
        o.rotation_euler = (0, math.radians(90), 0)    # +Z end -> +X
    return _finish(o, m, group, bevel)


def beam(group, p0, p1, w, h, m, bevel=0.025):
    """A box running from p0 to p1, w wide and h deep."""
    p0 = Vector(p0); p1 = Vector(p1)
    d = p1 - p0
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(p0 + p1) * 0.5)
    o = bpy.context.active_object
    o.scale = (w, d.length, h)
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = d.to_track_quat('Y', 'Z')
    return _finish(o, m, group, bevel)


def rod(group, p0, p1, r, m, verts=8, r2=None):
    p0 = Vector(p0); p1 = Vector(p1)
    d = p1 - p0
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d.length, location=(p0 + p1) * 0.5, vertices=verts)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=d.length, location=(p0 + p1) * 0.5, vertices=verts)
    o = bpy.context.active_object
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = d.to_track_quat('Z', 'Y')
    return _finish(o, m, group, 0.0)


# ---------------------------------------------------------------- hull
BARREL_Z = 2.87         # the bore's height
TRUNNION_Y = -0.9       # the trunnion, over the back half of the hull
MUZZLE_Y = 2.2
DECK = 2.45             # hull roof

box(HULL, (0, -0.65, 2.1), (1.7, 1.9, 0.7), ARMOR, bevel=0.05)              # main hull
box(HULL, (0, -0.65, 1.62), (1.2, 1.6, 0.3), DARK, bevel=0.04)              # belly pan
box(HULL, (0, 0.42, 2.2), (1.5, 0.5, 0.42), ARMOR, rot=(38, 0, 0), bevel=0.04)   # glacis
box(HULL, (0, 0.5, 1.85), (1.3, 0.34, 0.36), DARK, rot=(-30, 0, 0), bevel=0.03)  # chin
for sx in (-1, 1):
    # Applique plates along each flank, between the hips, and a vent under each.
    box(HULL, (sx * 0.87, -0.68, 2.16), (0.07, 0.86, 0.46), PLATE, bevel=0.02)
    for i in range(4):
        box(HULL, (sx * 0.9, -0.98 + i * 0.2, 2.16), (0.03, 0.09, 0.3), DARK, bevel=0.0)
    box(HULL, (sx * 0.62, -0.65, 1.5), (0.05, 1.1, 0.07), AMBER, bevel=0.0)  # belly running light
    # Trunnion cheeks: the two plates the gun hangs between.
    box(HULL, (sx * 0.33, TRUNNION_Y, 2.72), (0.09, 0.62, 0.62), ARMOR, bevel=0.03)
    box(HULL, (sx * 0.33, TRUNNION_Y + 0.36, 2.58), (0.09, 0.3, 0.3), ARMOR, rot=(-35, 0, 0), bevel=0.02)
    cyl(HULL, (sx * 0.4, TRUNNION_Y, BARREL_Z), 0.13, 0.1, DARK, axis='X', verts=14)
    cyl(HULL, (sx * 0.46, TRUNNION_Y, BARREL_Z), 0.07, 0.06, STEEL, axis='X', verts=10)
    # Whip antennae off the rear corners, raked back a little.
    cyl(HULL, (sx * 0.66, -1.42, DECK + 0.07), 0.07, 0.14, DARK, verts=10)
    rod(HULL, (sx * 0.66, -1.42, DECK + 0.1), (sx * 0.74, -1.62, 4.3), 0.022, DARK, verts=6, r2=0.008)
    # Lifting eyes on the roof corners.
    box(HULL, (sx * 0.7, 0.05, DECK + 0.03), (0.12, 0.05, 0.08), DARK, bevel=0.0)

# The face: a hatch on the glacis between two headlamps, and tow hooks on the chin.
box(HULL, (0, 0.5, 2.31), (0.5, 0.3, 0.04), PLATE, rot=(38, 0, 0), bevel=0.012)
for sx in (-1, 1):
    box(HULL, (sx * 0.56, 0.6, 2.2), (0.24, 0.05, 0.09), AMBER, rot=(38, 0, 0), bevel=0.0)
    box(HULL, (sx * 0.56, 0.585, 2.19), (0.3, 0.05, 0.15), DARK, rot=(38, 0, 0), bevel=0.01)
    box(HULL, (sx * 0.4, 0.68, 1.8), (0.08, 0.16, 0.12), STEEL, rot=(-30, 0, 0), bevel=0.015)
# Fire-control head, left of the bore so the barrel can dip past it.
box(HULL, (-0.56, -0.02, DECK + 0.2), (0.44, 0.5, 0.4), ARMOR, bevel=0.04)
box(HULL, (-0.56, 0.2, DECK + 0.38), (0.5, 0.2, 0.08), PLATE, bevel=0.015)       # brow
cyl(HULL, (-0.56, 0.24, DECK + 0.2), 0.13, 0.1, DARK, axis='Y', verts=16)
cyl(HULL, (-0.56, 0.28, DECK + 0.2), 0.09, 0.06, AMBER, axis='Y', verts=16, bevel=0.0)   # main optic
cyl(HULL, (-0.4, 0.25, DECK + 0.07), 0.035, 0.04, AMBER, axis='Y', verts=8, bevel=0.0)  # rangefinder
box(HULL, (-0.56, -0.34, DECK + 0.12), (0.3, 0.16, 0.24), DARK, bevel=0.02)
# Right of the bore: a rack of smoke dischargers and a stowage bin.
box(HULL, (0.58, -0.1, DECK + 0.1), (0.42, 0.6, 0.2), PLATE, bevel=0.03)
for i in range(3):
    cyl(HULL, (0.46 + i * 0.12, 0.26, DECK + 0.16), 0.045, 0.22, DARK, verts=8, rot=(-62, 0, 0), bevel=0.0)
# Engine deck at the back: louvres, two stacks, and the shell drum under the breech.
for i in range(5):
    box(HULL, (0.0, -1.28 - i * 0.065, DECK + 0.012), (0.5, 0.04, 0.03), DARK, rot=(25, 0, 0), bevel=0.0)
for sx in (-1, 1):
    cyl(HULL, (sx * 0.42, -1.72, 2.3), 0.07, 0.5, DARK, verts=10)
    cyl(HULL, (sx * 0.42, -1.72, 2.57), 0.085, 0.08, STEEL, verts=10)
cyl(HULL, (0, -1.78, 1.98), 0.33, 1.1, PLATE, axis='X', verts=20, bevel=0.03)    # shell drum
for sx in (-1, 1):
    cyl(HULL, (sx * 0.57, -1.78, 1.98), 0.2, 0.05, DARK, axis='X', verts=14)
    cyl(HULL, (sx * 0.6, -1.78, 1.98), 0.07, 0.04, AMBER, axis='X', verts=10, bevel=0.0)
cyl(HULL, (0, -1.78, 1.98), 0.345, 0.12, HAZARD, axis='X', verts=20, bevel=0.0)   # drum band
box(HULL, (0, -1.6, 2.33), (0.4, 0.3, 0.2), DARK, rot=(-30, 0, 0), bevel=0.02)   # feed chute up to the breech

# ---------------------------------------------------------------- gun
cyl(GUN, (0, (-1.0 + MUZZLE_Y) / 2, BARREL_Z), 0.1, MUZZLE_Y + 1.0, STEEL, axis='Y', verts=18, bevel=0.0)   # tube
cyl(GUN, (0, -0.4, BARREL_Z), 0.19, 1.5, ARMOR, axis='Y', verts=18, bevel=0.02)       # recoil sleeve
cyl(GUN, (0, 0.38, BARREL_Z), 0.19, 0.12, DARK, axis='Y', verts=18, r2=0.12, bevel=0.0)   # sleeve nose
box(GUN, (0, -1.38, BARREL_Z), (0.46, 0.54, 0.38), ARMOR, bevel=0.04)                 # breech block
box(GUN, (0, -1.67, BARREL_Z), (0.3, 0.06, 0.26), DARK, bevel=0.015)                  # breech door
box(GUN, (0.25, -1.38, BARREL_Z + 0.02), (0.06, 0.3, 0.12), STEEL, bevel=0.015)       # breech lever
for sx in (-1, 1):
    cyl(GUN, (sx * 0.14, -0.3, BARREL_Z + 0.2), 0.05, 1.3, STEEL, axis='Y', verts=10, bevel=0.0)   # recoil buffers
    cyl(GUN, (sx * 0.14, 0.38, BARREL_Z + 0.2), 0.062, 0.1, DARK, axis='Y', verts=10, bevel=0.0)
    for i in range(4):   # charge lamps along the sleeve
        box(GUN, (sx * 0.185, -0.85 + i * 0.26, BARREL_Z - 0.03), (0.03, 0.14, 0.06), AMBER, bevel=0.0)
# Gun shield ahead of the sleeve, raked back.
box(GUN, (0, 0.44, BARREL_Z + 0.05), (0.56, 0.05, 0.42), PLATE, rot=(-18, 0, 0), bevel=0.02)
# The clamp sits 1.4 m behind the muzzle (howitzer_barrel_probe reads the bore's line off it).
cyl(GUN, (0, MUZZLE_Y - 1.4, BARREL_Z), 0.135, 0.08, DARK, axis='Y', verts=18, bevel=0.0)
cyl(GUN, (0, 1.22, BARREL_Z), 0.15, 0.42, ARMOR, axis='Y', verts=18, bevel=0.03)      # bore evacuator
cyl(GUN, (0, MUZZLE_Y - 0.19, BARREL_Z), 0.17, 0.38, DARK, axis='Y', verts=18, bevel=0.02)   # muzzle brake
cyl(GUN, (0, MUZZLE_Y - 0.44, BARREL_Z), 0.125, 0.1, HAZARD, axis='Y', verts=18, bevel=0.0)  # warning band
for dy in (-0.27, -0.14):   # brake baffles, both sides
    box(GUN, (0, MUZZLE_Y + dy, BARREL_Z), (0.4, 0.06, 0.1), DARK, bevel=0.012)

# ---------------------------------------------------------------- legs
HIP_Z = 2.2
HIP_TOP = 2.56


def leg(sx, front):
    fy = 1.0 if front else -1.0
    hip = Vector((sx * 1.0, 0.07 if front else -1.42, HIP_Z))
    reach = 1.0 if front else 0.62   # the back pair stand closer in, under the breech
    knee = Vector((sx * 1.72, hip.y + fy * 0.42 * reach, 1.92))
    ankle = Vector((sx * 1.9, hip.y + fy * 0.62 * reach, 0.42))
    foot = Vector((sx * 1.93, hip.y + fy * 0.66 * reach, 0.0))
    out = Vector((sx, 0, 0))
    # Hip: a turret on the hull's corner. Its cap is the leg's highest point.
    cyl(LEGS, (hip.x, hip.y, HIP_Z + 0.02), 0.27, 0.56, DARK, verts=16, bevel=0.03)
    cyl(LEGS, (hip.x, hip.y, HIP_TOP - 0.04), 0.2, 0.08, PLATE, verts=16, bevel=0.015)
    cyl(LEGS, (hip.x, hip.y, HIP_TOP - 0.1), 0.285, 0.05, HAZARD, verts=16, bevel=0.0)
    # Thigh: out and slightly down to the knee, under an armour plate.
    beam(LEGS, hip + out * 0.12, knee, 0.3, 0.34, ARMOR, bevel=0.04)
    beam(LEGS, hip + out * 0.2 + Vector((0, 0, 0.2)), knee + Vector((0, 0, 0.2)), 0.38, 0.06, PLATE, bevel=0.02)
    # Knee: a drum across the leg's line.
    kd = (knee - hip); kd.z = 0; kd.normalize()
    side = Vector((-kd.y, kd.x, 0))
    rodlen = 0.46
    k = rod(LEGS, knee - side * rodlen / 2, knee + side * rodlen / 2, 0.21, DARK, verts=16)
    rod(LEGS, knee - side * (rodlen / 2 + 0.03), knee + side * (rodlen / 2 + 0.03), 0.09, STEEL, verts=10)
    # Knee guard: a spike raked up and out (it stays under the hip cap).
    rod(LEGS, knee + out * 0.05 + Vector((0, 0, 0.1)), knee + out * 0.34 + Vector((0, 0, 0.42)), 0.13, PLATE, verts=6, r2=0.015)
    # Shin: a long blade down to the ankle, with a splash plate on its outer face.
    beam(LEGS, knee, ankle, 0.22, 0.3, ARMOR, bevel=0.035)
    beam(LEGS, knee + out * 0.13 + Vector((0, 0, -0.25)), ankle + out * 0.1 + Vector((0, 0, 0.2)), 0.3, 0.05, PLATE, bevel=0.015)
    beam(LEGS, knee + out * 0.165 + Vector((0, 0, -0.62)), knee + out * 0.16 + Vector((0, 0, -0.78)) + (ankle - knee) * 0.0, 0.3, 0.03, HAZARD, bevel=0.0)
    # Piston from the thigh down to the shin.
    rod(LEGS, hip + out * 0.3 + Vector((0, 0, -0.22)), knee + (ankle - knee) * 0.32 - out * 0.1, 0.045, STEEL, verts=8)
    rod(LEGS, hip + out * 0.3 + Vector((0, 0, -0.22)), hip.lerp(knee, 0.55) + Vector((0, 0, -0.33)), 0.07, DARK, verts=8)
    # Foot: a spike under a splayed pad of three toes.
    rod(LEGS, ankle + Vector((0, 0, 0.12)), foot, 0.14, DARK, verts=10, r2=0.03)
    cyl(LEGS, (ankle.x, ankle.y, ankle.z + 0.1), 0.17, 0.16, STEEL, verts=12, bevel=0.02)
    for ang in (0, 120, 240):
        a = math.radians(ang + (90 if sx > 0 else -90) + (0 if front else 180) * 0)
        d = Vector((math.cos(a), math.sin(a), 0))
        beam(LEGS, ankle + Vector((0, 0, -0.02)) + d * 0.08, Vector((foot.x, foot.y, 0.06)) + d * 0.34, 0.2, 0.12, ARMOR, bevel=0.03)


for sx in (-1, 1):
    leg(sx, True)
    leg(sx, False)


# ---------------------------------------------------------------- join, export
def join(parts, name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name; o.data.name = name
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(38))
    except Exception as e:  # older Blender: leave it flat
        print("shade_smooth_by_angle unavailable:", e)
    return o


hull = join(HULL, "Hull")
legs = join(LEGS, "Legs")
barrel = join(GUN, "GunBarrel")
gun = bpy.data.objects.new("Gun", None)
bpy.context.scene.collection.objects.link(gun)
barrel.parent = gun


def bounds(objs):
    mn = Vector((1e9,) * 3); mx = Vector((-1e9,) * 3)
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for i in range(3):
                mn[i] = min(mn[i], w[i]); mx[i] = max(mx[i], w[i])
    return mn, mx


mn, mx = bounds([hull, legs, barrel])
tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in (hull, legs, barrel))
print("BOUNDS min %s max %s  tris %d" % (tuple(round(c, 3) for c in mn), tuple(round(c, 3) for c in mx), tris))
gmn, gmx = bounds([barrel])
print("GUN y %.3f..%.3f (Godot z %.3f..%.3f)" % (gmn.y, gmx.y, -gmx.y, -gmn.y))
assert abs(mn.z) < 5e-3 and abs(mx.z - 4.3) < 5e-3, "the model must stand 0..4.3 m so the fit is a scale of 1"
assert abs(mn.x + mx.x) < 2e-2 and abs(mn.y + mx.y) < 2e-2, "bounds must be centred or the fit shifts every measured number"

bpy.ops.object.select_all(action='DESELECT')
for o in (hull, legs, barrel, gun):
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_apply=True)
print("EXPORTED", OUT, os.path.getsize(OUT), "bytes")

# ---------------------------------------------------------------- previews
ctr = (mn + mx) * 0.5; rad = max((mx - mn).x, (mx - mn).y, (mx - mn).z)
t = bpy.data.objects.new("T", None); t.location = ctr
bpy.context.scene.collection.objects.link(t)
cam_d = bpy.data.cameras.new("C"); cam = bpy.data.objects.new("C", cam_d)
bpy.context.scene.collection.objects.link(cam)
cam.constraints.new('TRACK_TO').target = t
bpy.context.scene.camera = cam
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'MATERIAL'
sc.display.shading.show_cavity = True
sc.display.shading.show_shadows = True
sc.render.resolution_x = 900; sc.render.resolution_y = 900
VIEWS = [(1.1, 1.5, 0.45), (-1.4, 0.9, 0.3), (0.0, 1.9, 0.25), (1.9, 0.0, 0.2), (-0.9, -1.5, 0.7)]
for i, path in enumerate(ARGS):
    v = VIEWS[i % len(VIEWS)]
    cam.location = (ctr.x + rad * v[0], ctr.y + rad * v[1], ctr.z + rad * v[2])
    sc.render.filepath = os.path.abspath(path)
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path)
