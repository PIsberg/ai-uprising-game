import bpy, sys, os, math, json, mathutils
from mathutils import Vector

# blender --background --python fierce2.py -- <config.json>
cfgp = sys.argv[sys.argv.index("--")+1:][0]
cfg = json.load(open(cfgp))
IN, OUT, RENDER = cfg["in"], cfg["out"], cfg["render"]
RIG = cfg.get("rig", "skin")            # "skin" (weight+join) | "boneparent"
parts = cfg["parts"]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=IN)

arm  = next(o for o in bpy.data.objects if o.type=='ARMATURE')
mesh_objs = [o for o in bpy.data.objects if o.type=='MESH']
# strip stray junk (unparented Icosphere etc.)
for o in list(mesh_objs):
    if o.parent is None and o.name.lower().startswith("icosphere"):
        bpy.data.objects.remove(o, do_unlink=True)
mesh_objs = [o for o in bpy.data.objects if o.type=='MESH']
main = max(mesh_objs, key=lambda m: len(m.data.vertices))

# a material to reuse for added parts (prefer a dark/edge one)
def pick_mat(names):
    for want in ("Dark","Edge","Black","Main2","Grey","Main"):
        for m in names:
            if m and m.name == want: return m
    return names[0] if names else None
allmats = []
for m in mesh_objs:
    allmats += [mm for mm in m.data.materials if mm]
mat = pick_mat(allmats)

def make(p):
    t = p["type"]; loc = tuple(p["loc"]); rot = [math.radians(x) for x in p.get("rot",[0,0,0])]
    if t == "spike":
        bpy.ops.mesh.primitive_cone_add(vertices=p.get("verts",6), radius1=p["r"], radius2=0.0,
                                         depth=p["len"], location=loc)
    elif t == "blade":
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.active_object
    o.name = p["name"]
    if t == "blade":
        o.scale = tuple(p["size"])
    o.rotation_euler = mathutils.Euler(rot, 'XYZ')
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if mat:
        o.data.materials.clear(); o.data.materials.append(mat)
    o["_bone"] = p["bone"]
    return o

new = [make(p) for p in parts]

if RIG == "skin":
    for o in new:
        vg = o.vertex_groups.new(name=o["_bone"])
        vg.add(range(len(o.data.vertices)), 1.0, 'REPLACE')
    bpy.ops.object.select_all(action='DESELECT')
    for o in new: o.select_set(True)
    main.select_set(True); bpy.context.view_layer.objects.active = main
    bpy.ops.object.join()
    if not any(m.type=='ARMATURE' for m in main.modifiers):
        md = main.modifiers.new("Armature",'ARMATURE'); md.object = arm
else:  # childmesh: SKIN each part to its bone (separate scale-1 object).
    # Only skinning preserves true world size here (the part-meshes carry a 100x
    # object scale that mangles joins/parenting). A part weighted 100% to bone B
    # tracks B; rest position == where we place it.
    for o in new:
        vg = o.vertex_groups.new(name=o["_bone"])
        vg.add(range(len(o.data.vertices)), 1.0, 'REPLACE')
        md = o.modifiers.new("Armature", 'ARMATURE')
        md.object = arm

bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True,
                          export_animations=True, export_skins=True, export_apply=False)
print("EXPORTED", OUT)

# ---- auto-framed workbench render ----
mn = Vector((1e9,)*3); mx = Vector((-1e9,)*3)
for o in bpy.data.objects:
    if o.type=='MESH':
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            for i in range(3): mn[i]=min(mn[i],w[i]); mx[i]=max(mx[i],w[i])
ctr = (mn+mx)*0.5; rad = max((mx-mn).x,(mx-mn).z,(mx-mn).y)
cam_d=bpy.data.cameras.new("C"); cam=bpy.data.objects.new("C",cam_d)
bpy.context.scene.collection.objects.link(cam)
if cfg.get("cam"):
    cam.location = tuple(cfg["cam"]); ctr = Vector(tuple(cfg.get("tgt",[0,0,0])))
else:
    cam.location = (ctr.x+rad*0.9, ctr.y-rad*2.4, ctr.z+rad*0.5)
tgt=bpy.data.objects.new("T",None); tgt.location=ctr
bpy.context.scene.collection.objects.link(tgt)
cam.constraints.new('TRACK_TO').target=tgt
bpy.context.scene.camera=cam
sd=bpy.data.lights.new("S",'SUN'); s=bpy.data.objects.new("S",sd)
s.rotation_euler=(math.radians(55),0,math.radians(40)); sd.energy=4
bpy.context.scene.collection.objects.link(s)
sc=bpy.context.scene; sc.render.engine='BLENDER_WORKBENCH'
sc.render.resolution_x=720; sc.render.resolution_y=720; sc.render.filepath=RENDER
bpy.ops.render.render(write_still=True)
print("RENDERED", RENDER)
