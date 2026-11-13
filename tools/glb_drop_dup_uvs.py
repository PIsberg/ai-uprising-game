"""Drop the extra UV sets of a GLB that are byte-for-byte copies of TEXCOORD_0.

Some exporters (Tripo's, here) write the same UV layout two or three times and
point the normal map at the second copy. Godot imports TEXCOORD_1 as UV2 and
TEXCOORD_2 as CUSTOM0, 8 bytes a vertex each, and a surface carrying CUSTOM0
does not get the importer's vertex compression: BEHEMOTH-X stored 44 bytes a
vertex where its peers store 16 to 20 (#56).

A set is dropped only when it equals TEXCOORD_0 in EVERY primitive that has it,
so every material that named it can name set 0 instead and sample the same
texels. Nothing else in the file changes: positions, normals, indices, images,
nodes and names keep their bytes.

    python tools/glb_drop_dup_uvs.py --scan [dir]      # list what could be dropped (default assets/)
    python tools/glb_drop_dup_uvs.py <in.glb> <out.glb>
    python tools/glb_drop_dup_uvs.py --self-test       # the rules above against GLBs built in memory (CI)
"""
import json
import os
import struct
import sys
import tempfile

GLB_MAGIC = 0x46546C67
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942
COMPONENT_BYTES = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
SAFE_EXTENSIONS = ("KHR_materials_", "KHR_texture_transform")
TYPE_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


def read_glb(path):
    raw = open(path, "rb").read()
    magic, version, length = struct.unpack_from("<III", raw, 0)
    if magic != GLB_MAGIC:
        raise ValueError(f"{path} is not a GLB")
    off, gltf, binbuf = 12, None, b""
    while off < length:
        clen, ctype = struct.unpack_from("<II", raw, off)
        body = raw[off + 8: off + 8 + clen]
        if ctype == JSON_CHUNK:
            gltf = json.loads(body.decode("utf-8"))
        elif ctype == BIN_CHUNK:
            binbuf = body
        off += 8 + clen
    return gltf, binbuf, version, len(raw)


def accessor_bytes(gltf, binbuf, index):
    """The accessor's elements, tightly packed, or None when it cannot be compared (sparse, no view)."""
    acc = gltf["accessors"][index]
    if "sparse" in acc or "bufferView" not in acc:
        return None
    view = gltf["bufferViews"][acc["bufferView"]]
    size = COMPONENT_BYTES[acc["componentType"]] * TYPE_COUNT[acc["type"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride") or size
    if stride == size:
        return (acc["componentType"], acc["type"], binbuf[start:start + size * acc["count"]])
    return (acc["componentType"], acc["type"],
            b"".join(binbuf[start + i * stride: start + i * stride + size] for i in range(acc["count"])))


def duplicate_sets(gltf, binbuf):
    """UV set numbers (>= 1) that copy TEXCOORD_0 in every primitive carrying them."""
    seen, differs = set(), set()
    for mesh in gltf.get("meshes", []):
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            base = accessor_bytes(gltf, binbuf, attrs["TEXCOORD_0"]) if "TEXCOORD_0" in attrs else None
            for name, index in attrs.items():
                if not name.startswith("TEXCOORD_") or name == "TEXCOORD_0":
                    continue
                n = int(name.split("_")[1])
                seen.add(n)
                if base is None or accessor_bytes(gltf, binbuf, index) != base:
                    differs.add(n)
            # A morph target moving a UV set makes it differ from set 0 at runtime.
            for target in prim.get("targets", []):
                for name in target:
                    if name.startswith("TEXCOORD_") and name != "TEXCOORD_0":
                        differs.add(int(name.split("_")[1]))
    drop = seen - differs
    # Sets must stay contiguous (glTF) and Godot maps them by number: only drop a
    # set when every higher one goes too, so no surviving set is renumbered.
    return {n for n in drop if all(m in drop for m in seen if m > n)}


def retarget_materials(node, drop):
    """Point every textureInfo that named a dropped set at set 0. Returns how many changed."""
    changed = 0
    if isinstance(node, dict):
        # A textureInfo ("index") or a KHR_texture_transform override ("texCoord" alone).
        if node.get("texCoord", 0) in drop:
            del node["texCoord"]
            changed += 1
        for value in node.values():
            changed += retarget_materials(value, drop)
    elif isinstance(node, list):
        for value in node:
            changed += retarget_materials(value, drop)
    return changed


def remap_accessor_refs(gltf, remap):
    for mesh in gltf.get("meshes", []):
        for prim in mesh["primitives"]:
            prim["attributes"] = {k: remap[v] for k, v in prim["attributes"].items()}
            if "indices" in prim:
                prim["indices"] = remap[prim["indices"]]
            for target in prim.get("targets", []):
                for k in target:
                    target[k] = remap[target[k]]
    for skin in gltf.get("skins", []):
        if "inverseBindMatrices" in skin:
            skin["inverseBindMatrices"] = remap[skin["inverseBindMatrices"]]
    for anim in gltf.get("animations", []):
        for sampler in anim["samplers"]:
            sampler["input"] = remap[sampler["input"]]
            sampler["output"] = remap[sampler["output"]]


def strip(src, dst):
    gltf, binbuf, version, before = read_glb(src)
    drop = duplicate_sets(gltf, binbuf)
    if not drop:
        print(f"{src}: no UV set copies TEXCOORD_0, nothing written")
        return 1
    # Material extensions hold only textureInfos, which retarget_materials walks. Any
    # other extension may hold accessor or bufferView indices this script does not remap.
    foreign = [e for e in gltf.get("extensionsUsed", []) if not e.startswith(SAFE_EXTENSIONS)]
    if foreign:
        raise SystemExit(f"{src} uses extensions {foreign}: not handled, nothing written")
    dead = set()
    for mesh in gltf["meshes"]:
        for prim in mesh["primitives"]:
            for name in [k for k in prim["attributes"] if k.startswith("TEXCOORD_") and int(k.split("_")[1]) in drop]:
                dead.add(prim["attributes"].pop(name))
    retargeted = retarget_materials(gltf.get("materials", []), drop)

    # An accessor another primitive still uses stays.
    live = set()
    for mesh in gltf["meshes"]:
        for prim in mesh["primitives"]:
            live.update(prim["attributes"].values())
            if "indices" in prim:
                live.add(prim["indices"])
            for target in prim.get("targets", []):
                live.update(target.values())
    for skin in gltf.get("skins", []):
        if "inverseBindMatrices" in skin:
            live.add(skin["inverseBindMatrices"])
    for anim in gltf.get("animations", []):
        for sampler in anim["samplers"]:
            live.update((sampler["input"], sampler["output"]))
    dead -= live

    old_accessors = gltf["accessors"]
    remap, kept = {}, []
    for i, acc in enumerate(old_accessors):
        if i not in dead:
            remap[i] = len(kept)
            kept.append(acc)
    gltf["accessors"] = kept
    remap_accessor_refs(gltf, remap)

    used_views = {a["bufferView"] for a in kept if "bufferView" in a}
    used_views.update(img["bufferView"] for img in gltf.get("images", []) if "bufferView" in img)
    views, view_remap, out, new_views = gltf["bufferViews"], {}, bytearray(), []
    for i, view in enumerate(views):
        if i not in used_views:
            continue
        start = view.get("byteOffset", 0)
        out += b"\0" * ((-len(out)) % 4)
        view_remap[i] = len(new_views)
        new_view = dict(view, byteOffset=len(out))
        out += binbuf[start:start + view["byteLength"]]
        new_views.append(new_view)
    out += b"\0" * ((-len(out)) % 4)
    gltf["bufferViews"] = new_views
    for acc in kept:
        if "bufferView" in acc:
            acc["bufferView"] = view_remap[acc["bufferView"]]
    for img in gltf.get("images", []):
        if "bufferView" in img:
            img["bufferView"] = view_remap[img["bufferView"]]
    gltf["buffers"][0]["byteLength"] = len(out)

    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * ((-len(js)) % 4)
    total = 12 + 8 + len(js) + 8 + len(out)
    with open(dst, "wb") as f:
        f.write(struct.pack("<III", GLB_MAGIC, version, total))
        f.write(struct.pack("<II", len(js), JSON_CHUNK))
        f.write(js)
        f.write(struct.pack("<II", len(out), BIN_CHUNK))
        f.write(out)
    sets = ", ".join(f"TEXCOORD_{n}" for n in sorted(drop))
    print(f"{src}: dropped {sets} ({len(dead)} accessors, {retargeted} material slots now read set 0); "
          f"{before / 2**20:.1f} -> {total / 2**20:.1f} MB")
    return 0


def scan(root):
    found = 0
    for folder, _dirs, files in os.walk(root):
        for name in sorted(files):
            if not name.lower().endswith(".glb"):
                continue
            path = os.path.join(folder, name)
            try:
                gltf, binbuf, _version, _size = read_glb(path)
            except (ValueError, struct.error) as err:
                print(f"  skipped {path}: {err}")
                continue
            drop = duplicate_sets(gltf, binbuf)
            if drop:
                found += 1
                vertices = sum(gltf["accessors"][p["attributes"]["POSITION"]]["count"]
                               for m in gltf["meshes"] for p in m["primitives"])
                print(f"  {path}: {', '.join(f'TEXCOORD_{n}' for n in sorted(drop))} copy set 0 on {vertices} vertices")
    print(f"{found} GLB(s) carry a UV set that copies TEXCOORD_0")
    return found


def _tiny_glb(path, prims, normal_set=1):
    """A GLB of triangles. `prims` is a list of UV-set lists; each set is 3 (u, v) pairs."""
    binbuf, views, accessors = bytearray(), [], []

    def add(data, ctype, kind, count):
        views.append({"buffer": 0, "byteOffset": len(binbuf), "byteLength": len(data)})
        accessors.append({"bufferView": len(views) - 1, "componentType": ctype, "type": kind, "count": count})
        binbuf.extend(data)
        binbuf.extend(bytes(1) * ((-len(binbuf)) % 4))
        return len(accessors) - 1

    primitives = []
    for sets in prims:
        attrs = {"POSITION": add(struct.pack("<9f", 0, 0, 0, 1, 0, 0, 0, 1, 0), 5126, "VEC3", 3)}
        for n, uv in enumerate(sets):
            attrs["TEXCOORD_%d" % n] = add(struct.pack("<6f", *[c for pair in uv for c in pair]), 5126, "VEC2", 3)
        primitives.append({"attributes": attrs, "indices": add(struct.pack("<3H", 0, 1, 2), 5123, "SCALAR", 3), "material": 0})
    gltf = {"asset": {"version": "2.0"}, "buffers": [{"byteLength": len(binbuf)}], "bufferViews": views,
            "accessors": accessors, "meshes": [{"primitives": primitives}],
            "materials": [{"normalTexture": {"index": 0, "texCoord": normal_set},
                           "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}]}
    js = json.dumps(gltf).encode("utf-8")
    js += b" " * ((-len(js)) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", GLB_MAGIC, 2, 28 + len(js) + len(binbuf)))
        f.write(struct.pack("<II", len(js), JSON_CHUNK) + js)
        f.write(struct.pack("<II", len(binbuf), BIN_CHUNK) + bytes(binbuf))


def self_test():
    uv = [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)]
    other = [(0.0, 0.0), (0.5, 0.0), (0.0, 0.5)]
    cases = [
        ("both extra sets copy set 0", [[uv, uv, uv]], {1, 2}),
        ("set 1 differs", [[uv, other]], set()),
        # Dropping set 1 alone would renumber set 2 into UV2.
        ("set 1 copies but set 2 differs", [[uv, uv, other]], set()),
        ("set 2 copies, set 1 differs", [[uv, other, uv]], {2}),
        ("a copy in one primitive, not in the other", [[uv, uv], [uv, other]], set()),
        ("no extra set", [[uv]], set()),
    ]
    failed = []
    with tempfile.TemporaryDirectory() as tmp:
        src, dst = os.path.join(tmp, "in.glb"), os.path.join(tmp, "out.glb")
        for name, prims, want in cases:
            _tiny_glb(src, prims)
            gltf, binbuf, _v, _n = read_glb(src)
            got = duplicate_sets(gltf, binbuf)
            if got != want:
                failed.append("%s: would drop %s, expected %s" % (name, sorted(got), sorted(want)))
        # A strip keeps positions, indices and set 0 byte for byte, and repoints the material.
        _tiny_glb(src, [[uv, uv, uv]], normal_set=2)
        before, before_bin, _v, before_size = read_glb(src)
        saved = sys.stdout
        sys.stdout = open(os.devnull, "w")
        try:
            code = strip(src, dst)
        finally:
            sys.stdout.close()
            sys.stdout = saved
        after, after_bin, _v, after_size = read_glb(dst)
        prim_b, prim_a = before["meshes"][0]["primitives"][0], after["meshes"][0]["primitives"][0]
        if code != 0 or sorted(prim_a["attributes"]) != ["POSITION", "TEXCOORD_0"]:
            failed.append("strip left attributes %s" % sorted(prim_a["attributes"]))
        else:
            for key in ("POSITION", "TEXCOORD_0"):
                if accessor_bytes(before, before_bin, prim_b["attributes"][key]) != accessor_bytes(after, after_bin, prim_a["attributes"][key]):
                    failed.append("strip changed %s" % key)
            if accessor_bytes(before, before_bin, prim_b["indices"]) != accessor_bytes(after, after_bin, prim_a["indices"]):
                failed.append("strip changed the indices")
            if "texCoord" in after["materials"][0]["normalTexture"]:
                failed.append("the normal map still names a dropped set")
            if after_size >= before_size or len(after["accessors"]) != 3:
                failed.append("strip kept the dead accessors (%d left, %d -> %d bytes)" % (len(after["accessors"]), before_size, after_size))
            if duplicate_sets(after, after_bin):
                failed.append("a stripped file still reports a copy")
    if failed:
        print("glb_drop_dup_uvs self-test FAILED:")
        for line in failed:
            print("  " + line)
        return 1
    print("glb_drop_dup_uvs self-test OK (%d rule cases, 1 strip round trip)" % len(cases))
    return 0


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "--self-test":
        sys.exit(self_test())
    elif len(sys.argv) >= 2 and sys.argv[1] == "--scan":
        scan(sys.argv[2] if len(sys.argv) > 2 else "assets")
    elif len(sys.argv) == 3:
        sys.exit(strip(sys.argv[1], sys.argv[2]))
    else:
        sys.exit(__doc__)
