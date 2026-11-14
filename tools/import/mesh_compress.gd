extends RefCounted
## Stores a model's static surfaces in Godot's compressed vertex format (#56).
##
## The glTF importer (gltf_document.cpp, 4.7) asks for compressed vertices and
## then drops the request for a whole surface if ONE vertex has a tangent that
## is not perpendicular to its normal (a dot over 0.0001). Tangents it generates
## itself fail that on a handful of vertices where the UVs are degenerate: 2 of
## the 32,163 in BEHEMOTH-X's arm. The surface then stores 28 bytes a vertex
## instead of 16, and 858,000 vertices in 13 models did.
##
## compress() rebuilds those surfaces with each tangent made perpendicular to
## its normal (which is all the compressed format can hold anyway) and the
## compression flag set. Indices, LODs, materials and names are carried over.
## Skinned surfaces and meshes with blend shapes are left alone: the importer
## never compresses those, and this does not second-guess it.
##
## Used by tools/import/compress_meshes.gd (the post-import script) and by
## tests/mesh_compression_probe, which keeps uncompressed surfaces out.

## Surfaces under this many vertices are not worth a rebuild (12 bytes each).
const MIN_VERTICES := 256

## True when compress() would rebuild this surface: a static one stored
## uncompressed. `fmt` is the surface's format from the RenderingServer.
static func wants(mesh: ArrayMesh, fmt: int, vertex_count: int) -> bool:
	return mesh.get_blend_shape_count() == 0 \
		and (fmt & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) == 0 \
		and (fmt & Mesh.ARRAY_FORMAT_BONES) == 0 \
		and (fmt & Mesh.ARRAY_FORMAT_NORMAL) != 0 \
		and (fmt & Mesh.ARRAY_FLAG_USE_2D_VERTICES) == 0 \
		and vertex_count >= MIN_VERTICES

## Every ArrayMesh under `scene`, each once.
static func meshes(scene: Node) -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh is ArrayMesh and not out.has((n as MeshInstance3D).mesh):
			out.append((n as MeshInstance3D).mesh)
	return out

## [vertices stored uncompressed that compress() would take, all vertices].
static func census(scene: Node) -> Array[int]:
	var loose := 0
	var total := 0
	for mesh in meshes(scene):
		for s in mesh.get_surface_count():
			var d: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), s)
			total += int(d["vertex_count"])
			if wants(mesh, int(d["format"]), int(d["vertex_count"])):
				loose += int(d["vertex_count"])
	return [loose, total]

## Rebuilds every surface wants() names. Returns the vertices now compressed.
static func compress(scene: Node) -> int:
	var done := 0
	for mesh in meshes(scene):
		done += compress_mesh(mesh)
	return done

static func compress_mesh(mesh: ArrayMesh) -> int:
	var n := mesh.get_surface_count()
	var surfaces: Array[Dictionary] = []
	var any := false
	for s in n:
		var d: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), s)
		var take := wants(mesh, int(d["format"]), int(d["vertex_count"]))
		any = any or take
		surfaces.append({"take": take, "format": int(d["format"]), "vertices": int(d["vertex_count"]),
			"arrays": mesh.surface_get_arrays(s), "lods": _lods(d),
			"primitive": mesh.surface_get_primitive_type(s),
			"material": mesh.surface_get_material(s), "name": mesh.surface_get_name(s)})
	if not any:
		return 0
	# Surfaces keep their order (materials and overrides are indexed by it), so
	# the whole mesh is rebuilt, the untouched surfaces with the flags they had.
	var done := 0
	mesh.clear_surfaces()
	for s in n:
		var e: Dictionary = surfaces[s]
		var flags: int = e["format"] & (Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES | Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS \
			| Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE | Mesh.ARRAY_FLAG_USES_EMPTY_VERTEX_ARRAY)
		var arrays: Array = e["arrays"]
		if e["take"]:
			_square_tangents(arrays)
			flags |= Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
			done += int(e["vertices"])
		mesh.add_surface_from_arrays(e["primitive"], arrays, [], e["lods"], flags)
		mesh.surface_set_material(s, e["material"])
		mesh.surface_set_name(s, e["name"])
	return done

## The surface's LODs as add_surface_from_arrays wants them: edge length -> indices.
static func _lods(d: Dictionary) -> Dictionary:
	var out := {}
	var wide: bool = int(d["vertex_count"]) > 65535
	for lod: Dictionary in d.get("lods", []):
		var bytes: PackedByteArray = lod["index_data"]
		var idx: PackedInt32Array
		if wide:
			idx = bytes.to_int32_array()
		else:
			idx.resize(bytes.size() / 2)
			for i in idx.size():
				idx[i] = bytes.decode_u16(i * 2)
		out[float(lod["edge_length"])] = idx
	return out

## Each tangent loses its component along the normal (Gram-Schmidt) and is
## renormalised; its handedness (w) is kept. A tangent that was parallel to the
## normal gets any perpendicular: its UVs were degenerate, so it had no meaning.
static func _square_tangents(arrays: Array) -> void:
	if arrays[Mesh.ARRAY_TANGENT] == null or arrays[Mesh.ARRAY_NORMAL] == null:
		return
	var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tan: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	for i in nrm.size():
		var nv := nrm[i].normalized()
		var t := Vector3(tan[i * 4], tan[i * 4 + 1], tan[i * 4 + 2])
		t -= nv * nv.dot(t)
		if t.length_squared() < 1e-8:
			t = nv.cross(Vector3.UP if absf(nv.y) < 0.99 else Vector3.RIGHT)
		t = t.normalized()
		tan[i * 4] = t.x
		tan[i * 4 + 1] = t.y
		tan[i * 4 + 2] = t.z
	arrays[Mesh.ARRAY_TANGENT] = tan
