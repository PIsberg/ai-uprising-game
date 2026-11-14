"""Fail when the imported assets a release ships grow past their budget (#56).

The release pack is almost entirely `.godot/imported`: 341 of 343 MB on
2026-10-08. This sums the imported files of every tracked `.import` whose
source the export ships (everything outside the export's exclude_filter:
tests/, tools/, docs/), so build size is checked in CI after the import step
instead of only when someone runs tools/build_release.ps1 by hand.

Two budgets, both a ratchet: lower them when an asset pass lands, raise them
only on purpose, in the same commit as the asset that needs it.
  * all shipped imports together: TOTAL_BUDGET
  * any single imported file:      FILE_BUDGET

Also fails on a texture over LOSSLESS_BUDGET imported lossless (compress/mode=0):
2D art belongs in lossy WebP, a texture on a mesh in VRAM-compressed form with
mipmaps. Headless imports never run the editor's "detect 3D" step, so a model
texture extracted on a headless import stays lossless until someone sets it.

Also fails on a tracked `.import` whose source file is gone: a screenshot a
probe once saved into res:// leaves its stub behind (16 at the project root on
2026-10-08), and the editor re-imports nothing for it.

Also fails on a shipped model (.glb/.gltf/.fbx/.obj) that no game file names by
path: the export packs every resource (export_filter=all_resources), so a model
superseded by a fork or a v2 keeps shipping: 17.7 MB of imports on 2026-10-17
(robot_dog.glb under robot_dog_v2, EyeDrone_fishbot.glb, four cars, five
blasters, the reverted health-pack model and the textures only it used).
References from tests/, tools/ and docs/ do not count, since those do not ship.

Also fails on a shipped GLB that carries a UV set copying TEXCOORD_0 byte for
byte (some exporters write the layout two or three times). Godot imports the
copies as UV2 and CUSTOM0, 16 bytes a vertex that nothing samples, and a surface
with them misses the importer's vertex compression: six robots did on 2026-11-12.
`python tools/glb_drop_dup_uvs.py <in> <out>` drops them and changes nothing else.

Also fails on a shipped model imported with `meshes/create_shadow_meshes=true`
(the importer's default). The shadow mesh is a second, position-only copy of
every mesh for the shadow and depth passes: 19.2 MB of the 220.4 shipped on
2026-11-13, and tools/shadow_mesh_ab.tscn measured no GPU time for it (7 models,
8 or 16 copies under two shadowed lights: at most 0.04 ms either way, inside the
run-to-run noise, where the shadow passes themselves cost 7.8 ms).

    python tools/check_import_budget.py     # needs a populated .godot (run --import first)
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_drop_dup_uvs  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MB = 1024 * 1024
TOTAL_BUDGET = 192 * MB  # 2026-11-13: the HOWITZER is built from primitives (#406), 201.2 -> 189.4 MB
FILE_BUDGET = 40 * MB
# A texture imported lossless (compress/mode=0) ships as a lossless WebP and, on a
# mesh, uploads uncompressed with no mipmaps: the 23 comics were 1.2-1.5 MB each
# (0.4 lossy) and nine robot maps sat in VRAM at 16 MB apiece. Lossless is right for
# small UI art and palette sheets only, so a big one is an import-settings mistake.
LOSSLESS_BUDGET = 1 * MB
LOSSLESS = re.compile(r'^importer="texture"$.*^compress/mode=0$', re.MULTILINE | re.DOTALL)
EXCLUDED = ("tests/", "tools/", "docs/")  # export_presets.cfg exclude_filter
DEST = re.compile(r'^dest_files=\[(.*)\]', re.MULTILINE)
MODEL_EXT = (".glb", ".gltf", ".fbx", ".obj")
# Files that can name a model by its res:// path. A .gltf names its textures and
# buffers by bare uri, which is why only models are checked here.
REF_EXT = (".gd", ".tscn", ".tres", ".gdshader", ".cfg", ".lvl", ".json", ".godot")


def unreferenced_models(shipped: list) -> list:
    """Shipped models whose path appears in no shipped game file."""
    out = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True)
    corpus = []
    for path in out.stdout.splitlines():
        if path.startswith(EXCLUDED) or not path.endswith(REF_EXT):
            continue
        try:
            with open(os.path.join(ROOT, path), encoding="utf-8", errors="ignore") as f:
                corpus.append(f.read())
        except OSError:
            continue
    text = "\n".join(corpus)
    return [src for src in shipped if src.endswith(MODEL_EXT) and ("res://" + src) not in text]


def duplicate_uv_sets(shipped: list) -> list:
    """(source, set names) for every shipped GLB with a UV set that copies set 0."""
    found = []
    for src in shipped:
        if not src.lower().endswith(".glb"):
            continue
        gltf, binbuf, _version, _size = glb_drop_dup_uvs.read_glb(os.path.join(ROOT, src))
        drop = glb_drop_dup_uvs.duplicate_sets(gltf, binbuf)
        if drop:
            found.append((src, ", ".join("TEXCOORD_%d" % n for n in sorted(drop))))
    return found


def shadow_meshes_on(shipped: list) -> list:
    """Shipped models whose .import still asks for a shadow mesh."""
    out = []
    for src in shipped:
        if not src.lower().endswith((".glb", ".gltf", ".fbx", ".obj")):
            continue
        with open(os.path.join(ROOT, src + ".import"), encoding="utf-8") as f:
            if re.search(r"^meshes/create_shadow_meshes=true\s*$", f.read(), re.M):
                out.append(src)
    return out


def main() -> int:
    out = subprocess.run(["git", "ls-files", "*.import"], cwd=ROOT, capture_output=True, text=True, check=True)
    total = 0
    missing = []
    rows = []
    stale = []
    lossless = []
    for imp in out.stdout.splitlines():
        src = imp[: -len(".import")]
        if not os.path.isfile(os.path.join(ROOT, src)):
            stale.append(imp)
            continue
        if src.startswith(EXCLUDED):
            continue
        with open(os.path.join(ROOT, imp), encoding="utf-8") as f:
            text = f.read().replace("\r\n", "\n")
        m = DEST.search(text)
        if not m:
            continue
        size = 0
        for dest in re.findall(r'"res://([^"]+)"', m.group(1)):
            full = os.path.join(ROOT, dest)
            if os.path.isfile(full):
                size += os.path.getsize(full)
            else:
                missing.append(dest)
        total += size
        rows.append((size, src))
        if size > LOSSLESS_BUDGET and LOSSLESS.search(text):
            lossless.append((size, src))
    if missing:
        print("Import budget: %d imported file(s) missing; run `godot --headless --path . --import` first" % len(missing))
        for d in missing[:10]:
            print("  " + d)
        return 1
    rows.sort(reverse=True)
    errors = ["%s: tracked, but its source file is gone (git rm it)" % s for s in stale]
    if total > TOTAL_BUDGET:
        errors.append("shipped imports total %.1f MB, budget %d MB" % (total / MB, TOTAL_BUDGET // MB))
    for size, src in lossless:
        errors.append("%s is imported lossless (%.1f MB): set compress/mode=1 (lossy) for 2D art, "
                      "2 (VRAM compressed, mipmaps on) for a texture on a mesh" % (src, size / MB))
    for src in unreferenced_models([src for _, src in rows]):
        errors.append("%s ships but no scene, script or resource loads it (git rm it and its .import)" % src)
    for src in shadow_meshes_on([src for _, src in rows]):
        errors.append("%s imports a shadow mesh: set meshes/create_shadow_meshes=false in its .import" % src)
    for src, sets in duplicate_uv_sets([src for _, src in rows]):
        errors.append("%s carries %s as a copy of TEXCOORD_0: drop it with tools/glb_drop_dup_uvs.py" % (src, sets))
    for size, src in rows:
        if size > FILE_BUDGET:
            errors.append("%s imports to %.1f MB, per-file budget %d MB" % (src, size / MB, FILE_BUDGET // MB))
    print("Import budget: %.1f MB shipped across %d assets (budget %d MB); largest:"
          % (total / MB, len(rows), TOTAL_BUDGET // MB))
    for size, src in rows[:5]:
        print("  %6.1f MB  %s" % (size / MB, src))
    if errors:
        print("Failed:")
        for e in errors:
            print("  " + e)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
