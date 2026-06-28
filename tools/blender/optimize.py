import bpy, sys, os

# optimize.py — shrink a heavy glTF for game use: downsize oversized textures and
# re-export with Draco mesh compression. Skinned meshes are left untouched (no
# decimation) so rigs/weights survive.
#   blender -b --factory-startup -P optimize.py -- <in.glb> <out.glb> [maxtex]
a = sys.argv[sys.argv.index("--") + 1:]
src, dst = a[0], a[1]
maxtex = int(a[2]) if len(a) > 2 else 1024

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

# Downsize any texture whose largest dimension exceeds maxtex.
scaled = 0
for img in bpy.data.images:
    if img.size[0] == 0 or img.size[1] == 0:
        continue
    w, h = img.size[0], img.size[1]
    m = max(w, h)
    if m > maxtex:
        f = maxtex / float(m)
        img.scale(max(1, int(w * f)), max(1, int(h * f)))
        img.pack()
        scaled += 1
print("SCALED_IMAGES", scaled)

# NOTE: no Draco — Godot 4.7's glTF importer doesn't decode Draco-compressed
# meshes (the .scn silently fails to build). Texture downscaling above is the
# real size win; meshes stay uncompressed so they import cleanly.
bpy.ops.export_scene.gltf(
    filepath=dst,
    export_format='GLB',
    export_draco_mesh_compression_enable=False,
    export_image_format='AUTO',
    export_yup=True,
)
print("WROTE", dst, os.path.getsize(dst))
