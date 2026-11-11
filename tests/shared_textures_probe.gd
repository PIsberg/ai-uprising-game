extends Node
## Probe: no imported model stores the same texture twice (#56).
## Godot's glTF importer, in "embed as Basis Universal" mode, builds a new
## texture each time a material asks for an image. The RONIN's model has 8
## distinct pictures and shipped 37 textures: 26 MB of its 38 MB import were
## copies, and seven more models carried 12 MB of them between them. The
## post-import script tools/import/share_textures.gd points every material at
## one texture per picture; a model added without it brings the copies back.
## For every model under assets/models (.glb, .gltf, .fbx): the textures its
## materials hold are as many as differ in content
## (tools/import/texture_share.gd census, the script's own content key).
##   godot --headless --path . --audio-driver Dummy res://tests/shared_textures_probe.tscn

const TextureShare := preload("res://tools/import/texture_share.gd")
const MODEL_EXT := ["glb", "gltf", "fbx"]

func _scan(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if MODEL_EXT.has(f.get_extension().to_lower()):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), out)

func _ready() -> void:
	var models: Array = []
	_scan("res://assets/models", models)
	var copies: Array = []
	var stored_all := 0
	var checked := 0
	for path: String in models:
		var scene := load(path) as PackedScene
		if scene == null:
			continue
		var root := scene.instantiate()
		var c: Array = TextureShare.census(root)
		root.free()
		checked += 1
		stored_all += int(c[0])
		if int(c[0]) != int(c[1]):
			copies.append("%s: %d stored, %d distinct" % [path.trim_prefix("res://"), c[0], c[1]])
	# The census must be able to see a copy, or an empty list means nothing: two
	# materials with separate textures made from the same image are 2 stored, 1 distinct.
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.6, 0.9))
	var twin := Node3D.new()
	for i in 2:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = ImageTexture.create_from_image(img)
		mesh.material = mat
		mi.mesh = mesh
		twin.add_child(mi)
	var seen: Array = TextureShare.census(twin)
	var sees := seen == [2, 1]
	var merged: int = TextureShare.share(twin, {})
	var after: Array = TextureShare.census(twin)
	var shares := merged == 1 and after == [1, 1]
	twin.free()
	print("%s the census sees two textures of one image as a copy %s" % ["OK  " if sees else "FAIL", seen])
	print("%s sharing repoints the copy and leaves one %s" % ["OK  " if shares else "FAIL", after])
	var clean := copies.is_empty() and checked > 30
	print("%s no model stores a texture twice (%d models, %d textures)%s" % ["OK  " if clean else "FAIL", checked, stored_all,
		"" if copies.is_empty() else "\n    " + "\n    ".join(copies)])
	var ok := sees and shares and clean
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
