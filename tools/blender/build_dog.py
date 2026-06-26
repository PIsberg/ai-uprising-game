import bpy, sys, os, math
from mathutils import Vector

# blender --background --python build_dog.py -- <render_png>
RENDER = sys.argv[sys.argv.index("--")+1:][0]
OUT = os.path.abspath("assets/models/robots/robot_dog.glb")

bpy.ops.wm.read_factory_settings(use_empty=True)

# --- materials ---
def mat(name, col, metal=0.85, rough=0.4, emis=None, ee=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    b.inputs['Base Color'].default_value = (col[0], col[1], col[2], 1)
    b.inputs['Metallic'].default_value = metal
    b.inputs['Roughness'].default_value = rough
    if emis:
        b.inputs['Emission Color'].default_value = (emis[0], emis[1], emis[2], 1)
        b.inputs['Emission Strength'].default_value = ee
    return m

STEEL = mat("DogSteel", (0.17, 0.18, 0.21))
DARK = mat("DogDark", (0.08, 0.085, 0.1), 0.7, 0.5)
RED = mat("DogRed", (1.0, 0.12, 0.1), 0.3, 0.3, (1.0, 0.1, 0.08), 6.0)

parts = []
def box(name, loc, size, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.active_object; o.name = name
    o.scale = size
    o.rotation_euler = (math.radians(rot[0]), math.radians(rot[1]), math.radians(rot[2]))
    bpy.ops.object.transform_apply(rotation=True, scale=True)
    o.data.materials.append(m)
    parts.append(o)
    return o

def cyl(name, loc, r, h, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=loc, vertices=10)
    o = bpy.context.active_object; o.name = name
    o.rotation_euler = (math.radians(rot[0]), math.radians(rot[1]), math.radians(rot[2]))
    bpy.ops.object.transform_apply(rotation=True)
    o.data.materials.append(m)
    parts.append(o)
    return o

def sph(name, loc, r, m):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=12, ring_count=8)
    o = bpy.context.active_object; o.name = name
    o.data.materials.append(m)
    parts.append(o)
    return o

# Model faces -Y (front), Z up. A lean digitigrade attack-hound.
# Torso (slightly tapered, two segments).
box("Hip", (0, 0.45, 0.62), (0.5, 0.7, 0.42), STEEL)
box("Shoulders", (0, -0.45, 0.66), (0.56, 0.7, 0.46), STEEL)
box("Spine", (0, 0.0, 0.66), (0.4, 0.5, 0.34), DARK)
# Neck + head thrust forward and down (predatory).
box("Neck", (0, -0.85, 0.6), (0.26, 0.4, 0.26), DARK, rot=(35, 0, 0))
box("Head", (0, -1.12, 0.52), (0.34, 0.5, 0.34), STEEL)
box("Snout", (0, -1.42, 0.46), (0.24, 0.3, 0.22), DARK)
box("Jaw", (0, -1.4, 0.34), (0.22, 0.28, 0.08), DARK)
# Red sensor eyes + a chest core.
sph("EyeL", (0.13, -1.28, 0.58), 0.07, RED)
sph("EyeR", (-0.13, -1.28, 0.58), 0.07, RED)
box("Core", (0, -0.5, 0.7), (0.16, 0.06, 0.16), RED)
# Whip tail.
box("Tail", (0, 0.85, 0.7), (0.07, 0.5, 0.07), DARK, rot=(-40, 0, 0))
box("TailTip", (0, 1.05, 0.92), (0.05, 0.35, 0.05), STEEL, rot=(-20, 0, 0))
# Four digitigrade legs: thigh (angled) + shin (angled) + paw.
def leg(side, fb, x, ytop):
    s = "%s%s" % (side, fb)
    box("Thigh" + s, (x, ytop, 0.5), (0.16, 0.18, 0.42), STEEL, rot=(25 if fb == "F" else -25, 0, 0))
    box("Shin" + s, (x, ytop + (-0.18 if fb == "F" else 0.18), 0.24), (0.12, 0.13, 0.4), DARK, rot=(-30 if fb == "F" else 30, 0, 0))
    box("Paw" + s, (x, ytop + (-0.30 if fb == "F" else 0.30), 0.04), (0.13, 0.26, 0.08), STEEL)
leg("L", "F", 0.30, -0.5)
leg("R", "F", -0.30, -0.5)
leg("L", "B", 0.32, 0.55)
leg("R", "B", -0.32, 0.55)

# Join everything into one mesh.
bpy.ops.object.select_all(action='DESELECT')
for o in parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
body = bpy.context.active_object
body.name = "RobotDog"

bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True)
print("EXPORTED", OUT)

# preview
mn = Vector((1e9,)*3); mx = Vector((-1e9,)*3)
for c in body.bound_box:
    w = body.matrix_world @ Vector(c)
    for i in range(3): mn[i] = min(mn[i], w[i]); mx[i] = max(mx[i], w[i])
ctr = (mn+mx)*0.5; rad = max((mx-mn).x, (mx-mn).y, (mx-mn).z)
cam_d = bpy.data.cameras.new("C"); cam = bpy.data.objects.new("C", cam_d)
bpy.context.scene.collection.objects.link(cam)
cam.location = (ctr.x+rad*1.1, ctr.y-rad*1.6, ctr.z+rad*0.7)
t = bpy.data.objects.new("T", None); t.location = ctr
bpy.context.scene.collection.objects.link(t)
cam.constraints.new('TRACK_TO').target = t
bpy.context.scene.camera = cam
sd = bpy.data.lights.new("S", 'SUN'); s = bpy.data.objects.new("S", sd)
s.rotation_euler = (math.radians(55), 0, math.radians(40)); sd.energy = 4
bpy.context.scene.collection.objects.link(s)
sc = bpy.context.scene; sc.render.engine = 'BLENDER_WORKBENCH'
sc.render.resolution_x = 720; sc.render.resolution_y = 720
sc.render.filepath = os.path.abspath(RENDER)
bpy.ops.render.render(write_still=True)
print("RENDERED", RENDER)
