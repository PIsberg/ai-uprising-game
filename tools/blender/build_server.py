import bpy, sys, os, math
from mathutils import Vector

# blender --background --python build_server.py -- <render_png>
RENDER = sys.argv[sys.argv.index("--")+1:][0]
OUT = os.path.abspath("assets/models/robots/serving_bot.glb")

bpy.ops.wm.read_factory_settings(use_empty=True)

def mat(name, col, metal=0.7, rough=0.4, emis=None, ee=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    b.inputs['Base Color'].default_value = (col[0], col[1], col[2], 1)
    b.inputs['Metallic'].default_value = metal
    b.inputs['Roughness'].default_value = rough
    if emis:
        b.inputs['Emission Color'].default_value = (emis[0], emis[1], emis[2], 1)
        b.inputs['Emission Strength'].default_value = ee
    return m

SHELL = mat("SrvShell", (0.85, 0.86, 0.9), 0.4, 0.3)   # clean white-plastic cafe shell
DARK = mat("SrvDark", (0.1, 0.1, 0.12), 0.6, 0.5)
TRAY = mat("SrvTray", (0.5, 0.52, 0.58), 0.9, 0.3)
RED = mat("SrvRed", (1.0, 0.12, 0.1), 0.2, 0.3, (1.0, 0.1, 0.08), 7.0)

parts = []
def box(name, loc, size, m, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.active_object; o.name = name; o.scale = size
    o.rotation_euler = (math.radians(rot[0]), math.radians(rot[1]), math.radians(rot[2]))
    bpy.ops.object.transform_apply(rotation=True, scale=True)
    o.data.materials.append(m); parts.append(o); return o

def cyl(name, loc, r, h, m, rot=(0, 0, 0), v=16):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=loc, vertices=v)
    o = bpy.context.active_object; o.name = name
    o.rotation_euler = (math.radians(rot[0]), math.radians(rot[1]), math.radians(rot[2]))
    bpy.ops.object.transform_apply(rotation=True)
    o.data.materials.append(m); parts.append(o); return o

def sph(name, loc, r, m, sz=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=14, ring_count=10)
    o = bpy.context.active_object; o.name = name; o.scale = sz
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(m); parts.append(o); return o

# Model faces -Y (front), Z up. A cafe server bot turned sinister. ~1.9 tall.
# Wheeled rounded base.
cyl("Base", (0, 0, 0.18), 0.52, 0.36, DARK)
cyl("BaseTrim", (0, 0, 0.36), 0.5, 0.06, TRAY)
# Tapered body column.
cyl("Body", (0, 0, 0.95), 0.42, 1.2, SHELL)
box("Spine", (0, 0.18, 0.95), (0.5, 0.18, 1.1), DARK)   # back spine
# Three serving trays cantilevered out the front (-Y).
for i, z in enumerate([0.66, 1.02, 1.38]):
    box("Tray%d" % i, (0, -0.5, z), (0.74, 0.5, 0.05), TRAY)
    box("TrayLip%d" % i, (0, -0.74, z + 0.04), (0.74, 0.04, 0.06), DARK)
# Two thin arms gripping the top tray.
box("ArmL", (0.42, -0.28, 1.18), (0.08, 0.5, 0.08), SHELL, rot=(20, 0, 0))
box("ArmR", (-0.42, -0.28, 1.18), (0.08, 0.5, 0.08), SHELL, rot=(20, 0, 0))
# Rounded head with a screen face.
sph("Head", (0, 0, 1.78), 0.34, SHELL, sz=(1.0, 0.9, 0.92))
box("Screen", (0, -0.28, 1.8), (0.5, 0.06, 0.4), DARK)
# Evil: a red screen with angled angry eyes + a jagged grin.
box("FaceGlow", (0, -0.31, 1.8), (0.44, 0.02, 0.34), RED)
box("EyeL", (0.14, -0.33, 1.88), (0.12, 0.02, 0.05), DARK, rot=(0, 22, 0))
box("EyeR", (-0.14, -0.33, 1.88), (0.12, 0.02, 0.05), DARK, rot=(0, -22, 0))
box("Mouth", (0, -0.33, 1.7), (0.22, 0.02, 0.05), DARK)
# Pointy cat-ears (the cute server's silhouette, made sharp).
box("EarL", (0.2, 0.0, 2.08), (0.12, 0.1, 0.22), SHELL, rot=(0, 18, 0))
box("EarR", (-0.2, 0.0, 2.08), (0.12, 0.1, 0.22), SHELL, rot=(0, -18, 0))

bpy.ops.object.select_all(action='DESELECT')
for o in parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
body = bpy.context.active_object
body.name = "ServingBot"

bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True)
print("EXPORTED", OUT)

mn = Vector((1e9,)*3); mx = Vector((-1e9,)*3)
for c in body.bound_box:
    w = body.matrix_world @ Vector(c)
    for i in range(3): mn[i] = min(mn[i], w[i]); mx[i] = max(mx[i], w[i])
ctr = (mn+mx)*0.5; rad = max((mx-mn).x, (mx-mn).y, (mx-mn).z)
cam_d = bpy.data.cameras.new("C"); cam = bpy.data.objects.new("C", cam_d)
bpy.context.scene.collection.objects.link(cam)
cam.location = (ctr.x+rad*0.9, ctr.y-rad*1.7, ctr.z+rad*0.25)
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
