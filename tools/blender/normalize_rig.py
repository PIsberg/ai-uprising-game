import bpy, sys, os, math
from mathutils import Vector, Matrix

# normalize_rig.py — make an armature-rigged glTF usable as a game enemy by BAKING
# it to a static posed mesh: pose a chosen frame, apply the armature deformation
# into the geometry, delete the rig, then recenter on X/Y with feet at Z=0 and
# scale to a target height. Result imports as a clean static mesh (no skin/anim)
# that the runtime auto-fit handles reliably.
#   blender -b --factory-startup -P normalize_rig.py -- \
#       <in.glb> <out.glb> <target_h> <pose_frame|-1> <rotX> <rotY> <rotZ> [maxtex]
a = sys.argv[sys.argv.index("--") + 1:]
src, dst = a[0], a[1]
target_h = float(a[2])
pose_frame = int(a[3])
rot = (math.radians(float(a[4])), math.radians(float(a[5])), math.radians(float(a[6])))
maxtex = int(a[7]) if len(a) > 7 else 512
ctx = bpy.context

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

if pose_frame >= 0:
    ctx.scene.frame_set(pose_frame)

# Bake each skinned mesh's current (posed) deformation into its geometry, then
# drop the armatures — turns the rig into a static posed mesh.
bpy.ops.object.mode_set(mode='OBJECT')
for o in [o for o in bpy.data.objects if o.type == 'MESH']:
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    ctx.view_layer.objects.active = o
    for m in list(o.modifiers):
        if m.type == 'ARMATURE':
            try:
                bpy.ops.object.modifier_apply(modifier=m.name)
            except Exception as e:
                print("MODIFIER_FAIL", o.name, e)
bpy.ops.object.select_all(action='DESELECT')
for arm in [o for o in bpy.data.objects if o.type == 'ARMATURE']:
    arm.select_set(True)
if any(o.select_get() for o in bpy.data.objects):
    bpy.ops.object.delete()

def roots():
    return [o for o in bpy.data.objects if o.parent is None and o.type == 'MESH']

def apply_world(M):
    for o in roots():
        o.matrix_world = M @ o.matrix_world
    ctx.view_layer.update()

if any(rot):
    apply_world(Matrix.Rotation(rot[2], 4, 'Z') @ Matrix.Rotation(rot[1], 4, 'Y')
                @ Matrix.Rotation(rot[0], 4, 'X'))

# Measure static world bounds.
lo = Vector((1e18,) * 3); hi = Vector((-1e18,) * 3); found = False
for o in [o for o in bpy.data.objects if o.type == 'MESH']:
    for v in o.data.vertices:
        w = o.matrix_world @ v.co
        for i in range(3):
            lo[i] = min(lo[i], w[i]); hi[i] = max(hi[i], w[i])
        found = True

if found:
    size = hi - lo
    h = size.z if size.z > 0.0001 else 1.0   # Blender is Z-up
    s = target_h / h
    cx = (lo.x + hi.x) * 0.5
    cy = (lo.y + hi.y) * 0.5
    apply_world(Matrix.Translation(Vector((-cx * s, -cy * s, -lo.z * s))) @ Matrix.Scale(s, 4))
    print("NORM size=(%.2f,%.2f,%.2f) scale=%.5f" % (size.x, size.y, size.z, s))
else:
    print("NORM NO_MESH")

# Bake the transforms into the geometry so the export has clean identity nodes.
bpy.ops.object.select_all(action='DESELECT')
for o in [o for o in bpy.data.objects if o.type == 'MESH']:
    o.select_set(True)
    ctx.view_layer.objects.active = o
if roots():
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

for img in bpy.data.images:
    if img.size[0] == 0:
        continue
    m = max(img.size[0], img.size[1])
    if m > maxtex:
        f = maxtex / float(m)
        img.scale(max(1, int(img.size[0] * f)), max(1, int(img.size[1] * f)))
        img.pack()

bpy.ops.export_scene.gltf(
    filepath=dst, export_format='GLB',
    export_draco_mesh_compression_enable=False,
    export_animations=False, export_image_format='AUTO', export_yup=True)
print("WROTE", dst, os.path.getsize(dst))
