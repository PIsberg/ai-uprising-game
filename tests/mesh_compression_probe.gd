extends Node
## Probe: no model stores a static surface with uncompressed vertices (#56).
## Godot's glTF importer drops vertex compression for a whole surface when one
## vertex's tangent is not exactly perpendicular to its normal, which the
## tangents it generates itself are not on a few vertices with degenerate UVs:
## 2 of 32,163 in BEHEMOTH-X's arm. Such a surface stores 28 bytes a vertex
## instead of 16; 857,800 vertices in 24 models did, 9.8 MB. The post-import
## script tools/import/compress_meshes.gd rebuilds them compressed; a model
## added without it brings them back.
## For every model under assets/models (.glb, .gltf, .fbx): no static surface
## of MIN_VERTICES or more is stored uncompressed (tools/import/mesh_compress.gd
## census, the script's own test). Skinned surfaces and meshes with blend shapes
## are not counted: the engine does not compress those.
## And the rebuild is checked on a mesh made here: a surface with one skewed
## tangent comes out compressed, with its indices and its LOD intact.
##   godot --headless --path . --audio-driver Dummy res://tests/mesh_compression_probe.tscn

const MeshCompress := preload("res://tools/import/mesh_compress.gd")
const MODEL_EXT := ["glb", "gltf", "fbx"]

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _scan(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if MODEL_EXT.has(f.get_extension().to_lower()):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), out)

## A 20 x 20 grid of quads with a tangent on every vertex, one of them skewed
## off perpendicular the way the importer's generated ones are, and one LOD.
func _grid() -> ArrayMesh:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var tan := PackedFloat32Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	const N := 20
	for y in N + 1:
		for x in N + 1:
			pos.append(Vector3(x * 0.1, sin(x * 0.4) * 0.05, y * 0.1))
			nrm.append(Vector3.UP)
			tan.append_array([1.0, 0.0, 0.0, 1.0])
			uv.append(Vector2(x, y) / N)
	for y in N:
		for x in N:
			var i := y * (N + 1) + x
			idx.append_array([i, i + 1, i + N + 1, i + 1, i + N + 2, i + N + 1])
	var skew := Vector3(1.0, 0.4, 0.0).normalized()
	tan[7 * 4] = skew.x
	tan[7 * 4 + 1] = skew.y
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TANGENT] = tan
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {0.5: idx.slice(0, 600)}, 0)
	m.surface_set_name(0, "grid")
	m.surface_set_material(0, StandardMaterial3D.new())
	return m

func _ready() -> void:
	# (1) The rebuild itself.
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _grid()
	holder.add_child(mi)
	var mesh: ArrayMesh = mi.mesh
	var mat := mesh.surface_get_material(0)
	var idx0: PackedInt32Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var before: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), 0)
	var c0 := MeshCompress.census(holder)
	_check("an uncompressed static surface is counted", c0[0] == 441 and c0[1] == 441, "(%s)" % [c0])
	var done := MeshCompress.compress(holder)
	var after: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), 0)
	var now: Array = mesh.surface_get_arrays(0)
	_check("the rebuild takes it and stores it compressed", done == 441 and (int(after["format"]) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0
			and MeshCompress.census(holder)[0] == 0, "(%d vertices)" % done)
	var b0: int = (before["vertex_data"] as PackedByteArray).size() + (before["attribute_data"] as PackedByteArray).size()
	var b1: int = (after["vertex_data"] as PackedByteArray).size() + (after["attribute_data"] as PackedByteArray).size()
	_check("in fewer bytes", b1 < b0 * 0.7, "(%d -> %d)" % [b0, b1])
	var worst := 0.0
	var p1: PackedVector3Array = now[Mesh.ARRAY_VERTEX]
	var p0: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for y in 21:
		for x in 21:
			worst = maxf(worst, p1[y * 21 + x].distance_to(Vector3(x * 0.1, sin(x * 0.4) * 0.05, y * 0.1)))
	_check("vertices stay within 0.01 % of the mesh's size", p0.size() == 441 and worst < mesh.get_aabb().size.length() * 0.0001, "(%.4f mm)" % (worst * 1000.0))
	var t1: PackedFloat32Array = now[Mesh.ARRAY_TANGENT]
	var skewed := Vector3(t1[28], t1[29], t1[30])
	_check("the skewed tangent is squared to its normal, right-handed still", absf(skewed.dot(Vector3.UP)) < 0.01 and skewed.x > 0.99 and t1[31] > 0.0, "(%s)" % skewed)
	var lods: Array = after.get("lods", [])
	_check("indices, LOD, material and name are carried over", now[Mesh.ARRAY_INDEX] == idx0 and lods.size() == 1
			and (lods[0]["index_data"] as PackedByteArray).size() == 600 * 2 and is_equal_approx(lods[0]["edge_length"], 0.5)
			and mesh.surface_get_material(0) == mat and mesh.surface_get_name(0) == "grid", "(%d LOD)" % lods.size())
	_check("a second pass finds nothing to do", MeshCompress.compress(holder) == 0)
	holder.free()

	# (2) The shipped models.
	var models: Array = []
	_scan("res://assets/models", models)
	var loose: Array = []
	var loose_total := 0
	var total := 0
	var checked := 0
	for path: String in models:
		var scene := load(path) as PackedScene
		if scene == null:
			continue
		var root := scene.instantiate()
		var c := MeshCompress.census(root)
		root.free()
		checked += 1
		total += c[1]
		if c[0] > 0:
			loose_total += c[0]
			loose.append("%s: %d of %d vertices" % [path.trim_prefix("res://assets/models/"), c[0], c[1]])
	for line: String in loose:
		print("  uncompressed: %s" % line)
	_check("models were found", checked >= 50, "(%d)" % checked)
	_check("no model stores a static surface uncompressed", loose.is_empty(),
			"(%d models, %d of %d vertices, about %.1f MB; set import_script/path=\"res://tools/import/compress_meshes.gd\" in the .import and re-import)" % [
			loose.size(), loose_total, total, loose_total * 12.0 / 1048576.0])
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
