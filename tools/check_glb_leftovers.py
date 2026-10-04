"""Fail on texture files left next to a GLB that embeds its own images.

Godot's glTF importer can extract a model's embedded images into loose files
(`<model>_<n>.png`, `<model>_Image_<n>.jpg`). Every model in this repo imports
with `gltf/embedded_image_handling=2` (embed), so those loose copies are never
read by the model, yet the export ("all_resources") imports and ships each one.
On 2026-10-04 there were 208 of them, 2048x2048 extractions from before the
#102 shrink: 128 MB in git and 179 MB of the 540 MB exported pack (#56).

Fails (exit 1) when a tracked image named after a GLB in the same folder sits
beside it while that GLB embeds its images, unless a text resource references
the image by name.

    python tools/check_glb_leftovers.py
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMAGE = re.compile(r"^(?P<model>.+?)(?:_Image)?_\d+\.(?:png|jpe?g)$", re.IGNORECASE)
TEXT_EXT = (".tscn", ".tres", ".gd", ".gdshader", ".cfg", ".godot", ".json", ".lvl")


def tracked() -> list:
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True)
    return [p for p in out.stdout.splitlines() if p]


def main() -> int:
    files = tracked()
    present = set(files)
    corpus = []
    for p in files:
        if p.endswith(TEXT_EXT):
            with open(os.path.join(ROOT, p), encoding="utf-8", errors="replace") as f:
                corpus.append(f.read())
    corpus = "\n".join(corpus)
    errors = []
    for p in files:
        folder, name = os.path.split(p)
        m = IMAGE.match(name)
        if not m:
            continue
        glb = os.path.join(folder, m.group("model") + ".glb").replace(os.sep, "/")
        if glb not in present:
            continue
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
