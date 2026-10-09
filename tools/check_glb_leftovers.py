"""Fail on texture files left next to a GLB that embeds its own images.

Godot's glTF importer can extract a model's embedded images into loose files
named after the model: `<model>_<n>.png`, `<model>_Image_<n>.jpg`, or
`<model>_<image name>.png` (`Robot_Robot_Albedo.png`). Every model in this repo
imports with `gltf/embedded_image_handling=2` (embed), so those loose copies are
never read by the model, yet the export ("all_resources") imports and ships
each one. On 2026-10-04 there were 208 of them, 2048x2048 extractions from
before the #102 shrink: 128 MB in git and 179 MB of the 540 MB exported pack
(#56). The first version of this check knew only the numbered names, and eight
named extractions (10.7 MB imported) shipped past it until 2026-10-09.

Fails (exit 1) when a tracked image whose name starts with `<model>_` sits
beside `<model>.glb` while that GLB embeds its images, unless a text resource
references the image by name or a glTF model loads it by URI.

    python tools/check_glb_leftovers.py
"""
import json
import os
import re
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMAGE_EXT = (".png", ".jpg", ".jpeg", ".webp")
TEXT_EXT = (".tscn", ".tres", ".gd", ".gdshader", ".cfg", ".godot", ".json", ".lvl")


def tracked() -> list:
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True)
    return [p for p in out.stdout.splitlines() if p]


def image_uris(path: str) -> list:
    """External image URIs a .glb or .gltf loads, as file names."""
    with open(path, "rb") as f:
        data = f.read()
    try:
        if path.endswith(".glb"):
            doc = json.loads(data[20:20 + struct.unpack_from("<I", data, 12)[0]])
        else:
            doc = json.loads(data)
    except (ValueError, struct.error):
        return []
    return [os.path.basename(im["uri"]) for im in doc.get("images", [])
            if "uri" in im and not im["uri"].startswith("data:")]


def main() -> int:
    files = tracked()
    corpus = []
    models = {}  # folder -> GLB stems in it
    for p in files:
        full = os.path.join(ROOT, p)
        if not os.path.isfile(full):
            continue
        if p.endswith(TEXT_EXT):
            with open(full, encoding="utf-8", errors="replace") as f:
                corpus.append(f.read())
        if p.endswith((".glb", ".gltf")):
            corpus.extend(image_uris(full))
        if p.endswith(".glb"):
            folder, name = os.path.split(p)
            models.setdefault(folder, []).append(name[:-len(".glb")])
    corpus = "\n".join(corpus)
    errors = []
    for p in files:
        folder, name = os.path.split(p)
        if not name.lower().endswith(IMAGE_EXT):
            continue
        owners = [m for m in models.get(folder, []) if name.startswith(m + "_")]
        if not owners:
            continue
        glb = os.path.join(folder, max(owners, key=len) + ".glb").replace(os.sep, "/")
        imp = os.path.join(ROOT, glb + ".import")
        mode = None
        if os.path.exists(imp):
            with open(imp, encoding="utf-8") as f:
                hit = re.search(r"gltf/embedded_image_handling=(\d)", f.read())
                mode = hit.group(1) if hit else None
        if mode == "1":  # extract: the model really reads the loose files
            continue
        if name in corpus:
            continue
        errors.append("%s: leftover of %s (embedded_image_handling=%s), ships unused" % (p, glb, mode))
    if errors:
        print("GLB texture leftovers: %d file(s)" % len(errors))
        for e in errors:
            print("  " + e)
        return 1
    print("GLB texture leftovers: none")
    return 0


if __name__ == "__main__":
    sys.exit(main())
