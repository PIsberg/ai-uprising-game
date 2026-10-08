extends Node
## BeveledBoxMesh must wind its triangles the way Godot's own BoxMesh does, or the
## renderer culls the OUTSIDE of every box and draws its far inner faces instead
## (every builder wall, cover block and robot plate rendered inside-out until
## 2026-10-08: a sphere placed inside a beveled box showed straight through it).
## Ground truth is the engine's BoxMesh, not a remembered convention: for each
## triangle, the sign of cross(v1 - v0, v2 - v0) . outward_normal must match.
##   godot --headless --path . --audio-driver Dummy res://tests/bevel_winding_probe.tscn

func _sign_of(mesh: Mesh) -> Array: ## [positive, negative] triangle counts
	var a := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var pos := 0
	var neg := 0
	for t in range(0, idx.size(), 3):
		var i0 := idx[t]
		var face := (v[idx[t + 1]] - v[i0]).cross(v[idx[t + 2]] - v[i0])
		if face.length() < 1e-9:
			continue
		if face.dot(n[i0]) > 0.0:
			pos += 1
		else:
			neg += 1
	return [pos, neg]

func _ready() -> void:
	var ref := BoxMesh.new()
	ref.size = Vector3(1.4, 1.0, 0.6)
	var r := _sign_of(ref)
	var engine_positive: bool = r[0] > r[1]
	print("BoxMesh: %d triangles wound +, %d wound - (engine front faces are %s)" % [r[0], r[1], "+" if engine_positive else "-"])
	var ok: bool = r[0] == 0 or r[1] == 0
	for sz in [Vector3(1.4, 1.0, 0.6), Vector3(4, 2, 4), Vector3(0.2, 3, 0.2)]:
		var bb := BeveledBoxMesh.new()
		bb.size = sz
		bb.bevel = 0.06
		var b := _sign_of(bb)
		var good: int = b[0] if engine_positive else b[1]
		var bad: int = b[1] if engine_positive else b[0]
		print("BeveledBoxMesh %s: %d triangles match the engine, %d inside-out" % [sz, good, bad])
		if bad != 0 or good == 0:
			ok = false
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
