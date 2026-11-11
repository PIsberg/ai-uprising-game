extends RefCounted
## Shares identical textures between a scene's materials, and counts the ones
## that are not shared. The logic of tools/import/share_textures.gd (a
## post-import script, editor only), kept in a plain script so
## tests/shared_textures_probe can ask the same question of the imported models.

## Repoints every material texture under `node` at the first with the same
## content. Returns how many slots were repointed.
static func share(node: Node, first: Dictionary) -> int:
	var merged := 0
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				merged += _share_material(mi.mesh.surface_get_material(s), first)
		for s in mi.get_surface_override_material_count():
			merged += _share_material(mi.get_surface_override_material(s), first)
	for c in node.get_children():
		merged += share(c, first)
	return merged

static func _share_material(mat: Material, first: Dictionary) -> int:
	if mat == null:
		return 0
	var merged := 0
	for p in mat.get_property_list():
		if int(p["type"]) != TYPE_OBJECT:
			continue
		var tex = mat.get(p["name"])
		if not (tex is Texture2D):
			continue
		var key := content_key(tex)
		if key == "":
			continue
		if not first.has(key):
			first[key] = tex
		elif first[key] != tex:
			mat.set(p["name"], first[key])
			merged += 1
	return merged

## What a texture holds, as a string two textures share only when their stored
## bytes are the same. "" when it cannot be read (left alone).
static func content_key(tex: Texture2D) -> String:
	var data := PackedByteArray()
	var kind := tex.get_class()
	if tex is PortableCompressedTexture2D:
		# The compressed buffer itself (kept by the importer): no transcode needed.
		var raw = tex.get("_data")
		if raw is PackedByteArray:
			data = raw
	if data.is_empty():
		var img := tex.get_image()
		if img == null:
			return ""
		data = img.get_data()
		kind += ":%d" % img.get_format()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(data)
	return "%s %dx%d %s" % [kind, tex.get_width(), tex.get_height(), ctx.finish().hex_encode()]

## [stored, distinct]: how many textures the materials under `node` hold, and how
## many of those differ in content. Equal when nothing is stored twice.
static func census(node: Node) -> Array:
	var stored: Dictionary = {}
	var distinct: Dictionary = {}
	_census(node, stored, distinct)
	return [stored.size(), distinct.size()]

static func _census(node: Node, stored: Dictionary, distinct: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mats: Array = []
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				mats.append(mi.mesh.surface_get_material(s))
		for s in mi.get_surface_override_material_count():
			mats.append(mi.get_surface_override_material(s))
		for mat in mats:
			if mat == null:
				continue
			for p in (mat as Material).get_property_list():
				if int(p["type"]) != TYPE_OBJECT:
					continue
				var tex = (mat as Material).get(p["name"])
				if tex is Texture2D and not stored.has(tex):
					stored[tex] = true
					distinct[content_key(tex)] = true
	for c in node.get_children():
		_census(c, stored, distinct)
