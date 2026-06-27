import bpy, sys, os, math, mathutils
from mathutils import Vector

# blender --background --python smasher_build.py -- <render_png>
RENDER = sys.argv[sys.argv.index("--")+1:][0]
IN  = os.path.abspath("assets/models/robots/George.fbx")
TEX = os.path.abspath("assets/models/robots/George_Texture.png")
OUT = os.path.abspath("assets/models/robots/George_smasher.glb")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=IN)

arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
for o in list(meshes):
    if o.parent is None and o.name.lower().startswith("icosphere"):
        bpy.data.objects.remove(o, do_unlink=True)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
main = max(meshes, key=lambda m: len(m.data.vertices))

# Re-bind George's atlas texture so it survives the GLB export (FBX import often
# leaves the image unlinked).
if os.path.exists(TEX) and main.data.materials:
    bm = main.data.materials[0]
    bm.use_nodes = True
    nt = bm.node_tree
    bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if bsdf:
        img = bpy.data.images.load(TEX, check_existing=True)
        texn = nt.nodes.new('ShaderNodeTexImage')
        texn.image = img
        nt.links.new(texn.outputs['Color'], bsdf.inputs['Base Color'])

# Dark machined-steel material for the welded heavy plating.
steel = bpy.data.materials.new("SmasherSteel")
steel.use_nodes = True
sb = next(n for n in steel.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
sb.inputs['Base Color'].default_value = (0.16, 0.17, 0.2, 1.0)
sb.inputs['Metallic'].default_value = 0.92
sb.inputs['Roughness'].default_value = 0.42

# Heavy parts: (name, bone, location, size) in George's model space (Z up, ~6.5
# tall, FRONT = -Y). Rounded-feel pauldrons, a helmet shell + brow visor on the
# head, a front chest plate framing the reactor, and oversized smashing fists —
# the poster mech's heavy humanoid silhouette WITHOUT burying George in a box.
PARTS = [
    ("Pauldron_L", "Shoulder.L", (0.98, 0.10, 4.92), (0.95, 0.82, 0.86)),
    ("Pauldron_R", "Shoulder.R", (-0.98, 0.10, 4.92), (0.95, 0.82, 0.86)),
    ("Fist_L",     "LowerArm.L", (3.18, 0.13, 4.66), (0.95, 1.0, 1.0)),
    ("Fist_R",     "LowerArm.R", (-3.18, 0.13, 4.66), (0.95, 1.0, 1.0)),
    ("Helmet",     "Head",       (0.0, -0.05, 5.06), (0.95, 0.86, 0.82)),
    ("Brow",       "Head",       (0.0, -0.46, 5.04), (0.86, 0.22, 0.34)),
    ("ChestPlate", "Chest",      (0.0, -0.52, 3.55), (1.55, 0.55, 1.15)),
]

added = []
for name, bone, loc, size in PARTS:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    o.data.materials.clear()
    o.data.materials.append(steel)
    vg = o.vertex_groups.new(name=bone)
    vg.add(range(len(o.data.vertices)), 1.0, 'REPLACE')
    added.append(o)

# Join the heavy parts into George and keep the armature deform.
bpy.ops.object.select_all(action='DESELECT')
for o in added:
    o.select_set(True)
main.select_set(True)
bpy.context.view_layer.objects.active = main
bpy.ops.object.join()
if not any(m.type == 'ARMATURE' for m in main.modifiers):
    md = main.modifiers.new("Armature", 'ARMATURE')
    md.object = arm

bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True,
                          export_animations=True, export_skins=True, export_apply=False)
print("EXPORTED", OUT)

# Workbench preview.
mn = Vector((1e9,)*3); mx = Vector((-1e9,)*3)
for o in bpy.data.objects:
    if o.type == 'MESH':
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            for i in range(3): mn[i] = min(mn[i], w[i]); mx[i] = max(mx[i], w[i])
ctr = (mn+mx)*0.5; rad = max((mx-mn).x, (mx-mn).y, (mx-mn).z)
cam_d = bpy.data.cameras.new("C"); cam = bpy.data.objects.new("C", cam_d)
bpy.context.scene.collection.objects.link(cam)
cam.location = (ctr.x+rad*0.6, ctr.y-rad*2.2, ctr.z+rad*0.35)
tgt = bpy.data.objects.new("T", None); tgt.location = ctr
bpy.context.scene.collection.objects.link(tgt)
cam.constraints.new('TRACK_TO').target = tgt
bpy.context.scene.camera = cam
sd = bpy.data.lights.new("S", 'SUN'); s = bpy.data.objects.new("S", sd)
s.rotation_euler = (math.radians(55), 0, math.radians(40)); sd.energy = 4
bpy.context.scene.collection.objects.link(s)
sc = bpy.context.scene; sc.render.engine = 'BLENDER_WORKBENCH'
sc.render.resolution_x = 720; sc.render.resolution_y = 720; sc.render.filepath = RENDER
bpy.ops.render.render(write_still=True)
print("RENDERED", RENDER)
