extends SceneTree
## Where do an imported model's bytes go? (#56) The imported .scn is compressed,
## so its size says nothing about what is inside. This loads the scene and adds
## up what it holds: every stored texture (class, format, size, mipmaps, bytes
## in memory; and how many of them hold distinct pixels, since the importer's
## "embed as Basis Universal" mode stores one copy per material that uses an
## image) and every mesh surface (vertices, vertex/attribute/index/LOD bytes,
## blend shapes), plus the shadow meshes.
##   godot --headless --path . --script res://tools/scene_weight.gd -- res://assets/models/robots/robot-killer_model.glb [more.glb ...]
##   ... -- slots <model> [...]   one line per material texture slot with a hash of its pixels

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for path in args:
		if path == "slots":
			continue
		if args.has("slots"):
			_slots(path)
		else:
			_weigh(path)
	quit()

## `slots` mode: one line per material texture slot, with a hash of the pixels it
## samples. Two imports of a model show the same picture when these lines match
## (how share_textures.gd was checked: renders of some models differ run to run).
func _slots(path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		return
	var root := scene.instantiate()
	_slot_lines(root, root, path.get_file())
	root.free()

func _slot_lines(root: Node, n: Node, tag: String) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mesh := (n as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if mat == null:
				continue
			for p in mat.get_property_list():
				if int(p["type"]) == TYPE_OBJECT and mat.get(p["name"]) is Texture2D:
					var img := (mat.get(p["name"]) as Texture2D).get_image()
					var ctx := HashingContext.new()
					ctx.start(HashingContext.HASH_MD5)
					ctx.update(img.get_data())
					print("SLOT %s %s #%d %s %d %dx%d mips=%s %s" % [tag, root.get_path_to(n), s, p["name"], img.get_format(), img.get_width(), img.get_height(), img.has_mipmaps(), ctx.finish().hex_encode()])
	for c in n.get_children():
		_slot_lines(root, c, tag)

func _weigh(path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		print("%s: not a scene" % path)
		return
	var root := scene.instantiate()
	var textures: Dictionary = {}
	var meshes: Dictionary = {}
	_collect(root, textures, meshes)
	var tex_bytes := 0
	var by_kind: Dictionary = {}
	var distinct: Dictionary = {} ## content -> bytes: textures that hold the same pixels count once
	for t: Texture2D in textures:
		var img := t.get_image()
		var n := img.get_data().size() if img else 0
		tex_bytes += n
		if img:
			var ctx := HashingContext.new()
			ctx.start(HashingContext.HASH_MD5)
			ctx.update(img.get_data())
			distinct["%d %dx%d %s" % [img.get_format(), img.get_width(), img.get_height(), ctx.finish().hex_encode()]] = n
		var kind := "%s %s %dx%d%s" % [t.get_class(), _format(img), t.get_width(), t.get_height(), " +mips" if img and img.has_mipmaps() else ""]
		var row: Array = by_kind.get(kind, [0, 0])
		by_kind[kind] = [int(row[0]) + 1, int(row[1]) + n]
	var verts := 0
	var vbytes := 0
	var ibytes := 0
	var lod_bytes := 0
	var blend_bytes := 0
	var shadow_bytes := 0
	var surfaces := 0
	for m: ArrayMesh in meshes:
		var rid := m.get_rid()
		for s in m.get_surface_count():
			surfaces += 1
			var d := RenderingServer.mesh_get_surface(rid, s)
			verts += int(d.get("vertex_count", 0))
			vbytes += (d.get("vertex_data", PackedByteArray()) as PackedByteArray).size()
			vbytes += (d.get("attribute_data", PackedByteArray()) as PackedByteArray).size()
			vbytes += (d.get("skin_data", PackedByteArray()) as PackedByteArray).size()
			ibytes += (d.get("index_data", PackedByteArray()) as PackedByteArray).size()
			blend_bytes += (d.get("blend_shape_data", PackedByteArray()) as PackedByteArray).size()
			for lod: Dictionary in d.get("lods", []):
				lod_bytes += (lod.get("index_data", PackedByteArray()) as PackedByteArray).size()
		var sm := m.shadow_mesh
		if sm:
			for s in sm.get_surface_count():
				var d := RenderingServer.mesh_get_surface(sm.get_rid(), s)
				shadow_bytes += (d.get("vertex_data", PackedByteArray()) as PackedByteArray).size()
				shadow_bytes += (d.get("index_data", PackedByteArray()) as PackedByteArray).size()
	var mb := 1048576.0
	print("%s" % path)
	var distinct_bytes := 0
	for k in distinct:
		distinct_bytes += int(distinct[k])
	print("  textures: %d stored, %.1f MB; %d with distinct pixels, %.1f MB (the rest are copies: tools/import/share_textures.gd)"
		% [textures.size(), tex_bytes / mb, distinct.size(), distinct_bytes / mb])
	var kinds := by_kind.keys()
	kinds.sort()
	for k: String in kinds:
		print("    %2d x %-70s %6.1f MB" % [by_kind[k][0], k, by_kind[k][1] / mb])
	print("  meshes: %d (%d surfaces, %d vertices): vertices %.1f MB, indices %.1f MB, LODs %.1f MB, blend shapes %.1f MB, shadow meshes %.1f MB"
		% [meshes.size(), surfaces, verts, vbytes / mb, ibytes / mb, lod_bytes / mb, blend_bytes / mb, shadow_bytes / mb])
	print("  total in memory: %.1f MB" % ((tex_bytes + vbytes + ibytes + lod_bytes + blend_bytes + shadow_bytes) / mb))
	root.free()

func _format(img: Image) -> String:
	if img == null:
		return "?"
	return ClassDB.class_get_enum_constants("Image", "Format")[img.get_format()]

func _collect(n: Node, textures: Dictionary, meshes: Dictionary) -> void:
	if n is MeshInstance3D:
		var mesh := (n as MeshInstance3D).mesh
		if mesh is ArrayMesh:
			meshes[mesh] = true
			for s in mesh.get_surface_count():
				_material(mesh.surface_get_material(s), textures)
		for s in (n as MeshInstance3D).get_surface_override_material_count():
			_material((n as MeshInstance3D).get_surface_override_material(s), textures)
	for c in n.get_children():
		_collect(c, textures, meshes)

func _material(mat: Material, textures: Dictionary) -> void:
	if mat == null:
		return
	for p in mat.get_property_list():
		if int(p["type"]) == TYPE_OBJECT:
			var v = mat.get(p["name"])
			if v is Texture2D:
				textures[v] = true
