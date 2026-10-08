"""Decimate every mesh in a GLB and re-export it, headless.

    "C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" --background \
        --python tools/blender/decimate.py -- <in.glb> <out.glb> <ratio>

Meshes under 500 polygons are left alone (greebles, eyes). Blender keeps every
node, mesh and material name on export; the only rename it makes is suffixing
duplicate node names (.001, .002, ...), which Godot's importer would have
uniquified on its own anyway. Check with a JSON diff of the two GLBs' node and
material name sets before shipping a decimated model, and shoot it with
tests/model_view_probe next to the original.

First use (2026-09-12): rusty_claws_robot.glb at ratio 0.35 went from 950 755
to 332 752 triangles and 58.5 MB to 24.5 MB on disk, indistinguishable at game
scale (issue #56). 2026-10-04: robot-killer_model.glb (RONIN) at 0.35, 492 280
-> 175 300 triangles, 31.3 -> 21.2 MB; walking_robot_gun.glb (HOWITZER) at
0.45, 299 646 -> 134 885, 28.0 -> 18.6 MB. Node and material name sets
unchanged, model_view_probe shots indistinguishable side by side.
"""
import bpy
import sys

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst, ratio = argv[0], argv[1], float(argv[2])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
tris_before = 0
for ob in bpy.data.objects:
    if ob.type != "MESH":
        continue
    ob.data.calc_loop_triangles()
    tris_before += len(ob.data.loop_triangles)
    if len(ob.data.polygons) < 500:
        continue
    mod = ob.modifiers.new("dec", "DECIMATE")
    mod.ratio = ratio
    mod.use_collapse_triangulate = True
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_apply=True, export_yup=True,
                          export_animations=True, export_skins=True, export_image_format="AUTO")
print("TRIS_BEFORE", tris_before)
