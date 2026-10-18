"""Cut a static (rig-less) GLB into named limb parts, headless, so a script can
swing each part about its joint (PartRig) without splitting the mesh at runtime.

    "C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" --background \
        --python tools/blender/split_regions.py -- <in.glb> <out.glb> <cfg.json>

Every mesh is joined into one object first (material slots are kept), then each
face goes to the first region whose box holds its world-space centroid; the
faces no region claims stay in an object named by the config's "rest" key. The
boxes are in world coordinates after import (Blender: Z up). Each region
becomes its own object, so the exported GLB has one MeshInstance3D per region,
named after it, all under the original parent with its original transform.

Config:
    {"rest": "Body",
     "regions": [{"name": "ArmP", "min": [-9, 0.245, -0.36], "max": [9, 9, 0.22]}, ...]}

Why offline: BEHEMOTH-X (rusty_claws_robot.glb, 337k triangles in 12 meshes,
each mesh a material slice through the whole body) took about 1.3 s to cut
with PartRig.split_groups at spawn, a visible hitch as the boss arrives.
"""
import bmesh
import bpy
import json
import sys

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst, cfg_path = argv[0], argv[1], argv[2]
with open(cfg_path, encoding="utf-8") as f:
    cfg = json.load(f)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [ob for ob in bpy.data.objects if ob.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for ob in meshes:
    ob.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
whole = bpy.context.view_layer.objects.active
mw = whole.matrix_world


def region_of(c):
    for i, r in enumerate(cfg["regions"]):
        lo, hi = r["min"], r["max"]
        if all(lo[k] <= c[k] < hi[k] for k in range(3)):
            return i
    return -1


for g, r in enumerate(cfg["regions"]):
    bpy.ops.object.select_all(action="DESELECT")
    whole.select_set(True)
    bpy.context.view_layer.objects.active = whole
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_mode(type="FACE")
    bpy.ops.mesh.select_all(action="DESELECT")
    bm = bmesh.from_edit_mesh(whole.data)
    n = 0
    for face in bm.faces:
        if region_of(mw @ face.calc_center_median()) == g:
            face.select_set(True)
            n += 1
    bm.select_flush_mode()
    bmesh.update_edit_mesh(whole.data)
    if n == 0:
        sys.exit("region %s claims no faces" % r["name"])
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    cut = [ob for ob in bpy.context.selected_objects if ob != whole][0]
    cut.name = r["name"]
    cut.data.name = r["name"]
    print("REGION", r["name"], n)
whole.name = cfg.get("rest", "Body")
whole.data.name = whole.name
print("REST", whole.name, len(whole.data.polygons))
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_apply=True, export_yup=True,
                          export_animations=False, export_image_format="AUTO")
