import bpy, sys, os, collections, mathutils
a = sys.argv[sys.argv.index("--")+1:]
path = a[0]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)
print("\n##### ", os.path.basename(path), " #####")
meshes = [o for o in bpy.data.objects if o.type=='MESH']
arms   = [o for o in bpy.data.objects if o.type=='ARMATURE']
for m in meshes:
    print(f"MESH {m.name!r} verts={len(m.data.vertices)} polys={len(m.data.polygons)} "
          f"mats={[mm.name for mm in m.data.materials]} parent={m.parent.name if m.parent else '-'}")
# per-vertex-group dominant-weight extents (only meaningful for skinned mesh)
main = max(meshes, key=lambda m: len(m.data.vertices)) if meshes else None
if main:
    groups = {vg.index: vg.name for vg in main.vertex_groups}
    agg = collections.defaultdict(lambda:[mathutils.Vector((1e9,)*3), mathutils.Vector((-1e9,)*3)])
    for v in main.data.vertices:
        if not v.groups: continue
        g = max(v.groups, key=lambda gw: gw.weight)
        name = groups.get(g.group,'?')
        wv = main.matrix_world @ v.co
        box = agg[name]
        for i in range(3):
            box[0][i]=min(box[0][i],wv[i]); box[1][i]=max(box[1][i],wv[i])
    print("-- per-bone vertex extents (dominant weight) --")
    for name,(mn,mx) in sorted(agg.items()):
        print(f"  {name:16} min=({mn.x:.2f},{mn.y:.2f},{mn.z:.2f}) max=({mx.x:.2f},{mx.y:.2f},{mx.z:.2f})")
for arm in arms:
    print(f"ARMATURE {arm.name!r}: bones={[b.name for b in arm.data.bones]}")
print("ACTIONS:", [a.name for a in bpy.data.actions])
