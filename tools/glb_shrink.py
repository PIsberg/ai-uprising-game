"""Downscale the images embedded in a GLB in place, leaving every node, mesh,
material and accessor byte-identical. Only image bufferViews are rewritten (and
every bufferView's byteOffset is re-laid out to match). Usage:
    python glb_shrink.py <in.glb> <out.glb> [max_color=2048] [max_data=1024]
Data maps (normal / roughness / metallic / occlusion / ORM, found by material
reference) get the smaller cap; colour and emissive the larger. Prints a table.
"""
import sys, json, struct, io
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
MAX_COLOR = int(sys.argv[3]) if len(sys.argv) > 3 else 2048
MAX_DATA = int(sys.argv[4]) if len(sys.argv) > 4 else 1024

raw = open(src, "rb").read()
magic, version, length = struct.unpack_from("<III", raw, 0)
assert magic == 0x46546C67, "not a GLB"
off = 12
chunks = []
while off < length:
    clen, ctype = struct.unpack_from("<II", raw, off)
    chunks.append((ctype, raw[off + 8: off + 8 + clen]))
    off += 8 + clen
gltf = json.loads(chunks[0][1].decode("utf-8"))
binbuf = chunks[1][1]
views = gltf["bufferViews"]

# Classify textures by how materials use them.
data_tex = set()
for m in gltf.get("materials", []):
    pbr = m.get("pbrMetallicRoughness", {})
    for key in ("metallicRoughnessTexture",):
        if key in pbr: data_tex.add(pbr[key]["index"])
    for key in ("normalTexture", "occlusionTexture"):
        if key in m: data_tex.add(m[key]["index"])
data_img = {gltf["textures"][t]["source"] for t in data_tex if t < len(gltf.get("textures", []))}

def view_bytes(v):
    o = v.get("byteOffset", 0); return binbuf[o:o + v["byteLength"]]

new_data = {}   # view index -> bytes
rows = []
for i, img in enumerate(gltf.get("images", [])):
    if "bufferView" not in img: continue
    vi = img["bufferView"]; b = view_bytes(views[vi])
    im = Image.open(io.BytesIO(b)); w, h = im.size
    cap = MAX_DATA if i in data_img else MAX_COLOR
    if max(w, h) <= cap:
        rows.append((i, img.get("name", ""), img.get("mimeType", ""), f"{w}x{h}", "kept", len(b), len(b))); continue
    s = cap / max(w, h); nw, nh = max(1, round(w * s)), max(1, round(h * s))
    im2 = im.resize((nw, nh), Image.LANCZOS)
    out = io.BytesIO()
    if img.get("mimeType") == "image/jpeg":
        im2.convert("RGB").save(out, "JPEG", quality=90, optimize=True)
    else:
        im2.save(out, "PNG", optimize=True)
    nb = out.getvalue(); new_data[vi] = nb
    rows.append((i, img.get("name", ""), img.get("mimeType", ""), f"{w}x{h}->{nw}x{nh}", "shrunk", len(b), len(nb)))

# Re-lay the BIN chunk: every view in original order, 4-byte aligned.
out_bin = bytearray(); cursor = 0
for vi, v in enumerate(views):
    data = new_data.get(vi, view_bytes(v))
    pad = (-cursor) % 4
    out_bin += b"\0" * pad; cursor += pad
    v["byteOffset"] = cursor; v["byteLength"] = len(data)
    out_bin += data; cursor += len(data)
if cursor % 4: out_bin += b"\0" * ((-cursor) % 4)
gltf["buffers"][0]["byteLength"] = len(out_bin)
js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
js += b" " * ((-len(js)) % 4)
total = 12 + 8 + len(js) + 8 + len(out_bin)
with open(dst, "wb") as f:
    f.write(struct.pack("<III", magic, version, total))
    f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
    f.write(struct.pack("<II", len(out_bin), 0x004E4942)); f.write(out_bin)
before = sum(r[5] for r in rows); after = sum(r[6] for r in rows)
for r in rows: print("  img %2d %-28s %-10s %-22s %-6s %8.1f -> %6.1f KB" % (r[0], r[1][:28], r[2], r[3], r[4], r[5]/1024, r[6]/1024))
print("images: %.1f MB -> %.1f MB; file: %.1f MB -> %.1f MB" % (before/2**20, after/2**20, len(raw)/2**20, total/2**20))
