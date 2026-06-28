import bpy, sys, os
from mathutils import Vector, Matrix

# fit_keep_anim.py — normalize an armature-rigged glTF for game use WITHOUT baking
# to static (keeps the animation). Measures the posed bounds at a reference frame,
# then parents everything to an empty whose static transform scales the rig to a
# target height, centres it on X/Y and drops feet to Z=0. The animation plays
# underneath the empty, so the model is correctly placed AND animated in-engine.
#   blender -b --factory-startup -P fit_keep_anim.py -- \
#       <in.glb> <out.glb> <target_h> <ref_frame> <rotZ_deg> [maxtex]
import math
a = sys.argv[sys.argv.index("--") + 1:]
src, dst = a[0], a[1]
target_h = float(a[2])
ref_frame = int(a[3])
rotz = math.radians(float(a[4]))
maxtex = int(a[5]) if len(a) > 5 else 384
ctx = bpy.context

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
ctx.scene.frame_set(ref_frame)
ctx.view_layer.update()

# Posed world bounds at the reference frame (evaluated meshes).
dg = ctx.evaluated_depsgraph_get()
lo = Vector((1e18,) * 3); hi = Vector((-1e18,) * 3); found = False
for o in [o for o in bpy.data.objects if o.type == 'MESH']:
    ev = o.evaluated_get(dg)
    me = ev.to_mesh()
    for v in me.vertices:
        w = ev.matrix_world @ v.co
        for i in range(3):
            lo[i] = min(lo[i], w[i]); hi[i] = max(hi[i], w[i])
        found = True
    ev.to_mesh_clear()

size = hi - lo
h = size.z if size.z > 0.0001 else 1.0
s = target_h / h
cx = (lo.x + hi.x) * 0.5
cy = (lo.y + hi.y) * 0.5
print("FIT size=(%.2f,%.2f,%.2f) scale=%.5f" % (size.x, size.y, size.z, s))

# Parent every root to an empty, then set the empty's transform to scale/centre.
bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, 0, 0))
empty = ctx.active_object
for o in [o for o in bpy.data.objects if o.parent is None and o is not empty]:
    o.parent = empty
    o.matrix_parent_inverse = Matrix.Identity(4)
M = (Matrix.Translation(Vector((-cx * s, -cy * s, -lo.z * s)))
     @ Matrix.Rotation(rotz, 4, 'Z') @ Matrix.Scale(s, 4))
empty.matrix_world = M

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
    export_animations=True, export_image_format='AUTO', export_yup=True)
print("WROTE", dst, os.path.getsize(dst))
