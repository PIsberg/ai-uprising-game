extends Node3D
## What would capping a model's textures cost on screen? (#56)
##
## Renders one model with its textures at full size (A), with some of them capped
## (B), and at full size again (A2), in ONE process and from the same camera, at
## several distances. A against A2 is the noise floor, A against B the change.
## `python tools/texture_cap_report.py <out dir>` turns the frames into a table
## and side-by-side crops.
##
## Two separate runs cannot answer this: they differ by 30 to 99 dB on the same
## import (measured 2026-11-12 on five props, FSR2 off), which is as much as a
## 2K -> 1K cap changes. Both variants are rebuilt here from the imported texture
## (decompressed, mipmaps regenerated the same way), so block compression is in
## neither and only the resolution differs.
##
##   godot --path . res://tools/texture_cap_ab.tscn -- model=res://assets/models/props/Prop_Crate.gltf \
##       out=build/texcap cap=1024 slots=data dist=1,2,4
##   slots=data   normal, roughness, metallic, AO and ORM maps (the default)
##   slots=color  albedo and emission
##   slots=all    both

const DATA_SLOTS := ["normal_texture", "roughness_texture", "metallic_texture", "ao_texture", "orm_texture"]
const COLOR_SLOTS := ["albedo_texture", "emission_texture"]
const VIEWS := [["front", Vector3(0, 1, 1)], ["side", Vector3(1, 1, 0.04)], ["q3", Vector3(0.75, 1, 0.75)]]
const SETTLE_FRAMES := 6

var _out := "build/texcap"
var _slots: Array = DATA_SLOTS
## [material, slot, full texture, capped texture, texture as imported]
var _swaps: Array = []

func _ready() -> void:
	var model_path := "res://assets/models/props/Prop_Crate.gltf"
	var cap := 1024
	var dists: Array = [1.0, 2.0, 4.0]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("model="):
			model_path = a.trim_prefix("model=")
		elif a.begins_with("out="):
			_out = a.trim_prefix("out=")
		elif a.begins_with("cap="):
			cap = maxi(int(a.trim_prefix("cap=")), 4)
		elif a.begins_with("dist="):
			dists = []
			for d in a.trim_prefix("dist=").split(","):
				dists.append(maxf(float(d), 0.1))
		elif a == "slots=color":
			_slots = COLOR_SLOTS
		elif a == "slots=all":
			_slots = DATA_SLOTS + COLOR_SLOTS
	DirAccess.make_dir_recursive_absolute(_abs(_out))

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.6, 0.66)
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.09, 0.12)
	add_child(env)

	var model: Node3D = (load(model_path) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	# An imported model's idle animation still plays under a disabled process mode.
	for ap in model.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).stop()
	var aabb := _merged_aabb(model)
	model.position = Vector3(-aabb.get_center().x, -aabb.position.y, -aabb.get_center().z)
	var h: float = maxf(aabb.size.y, 0.5)
	var tag := model_path.get_file().get_basename()
	_build_swaps(model, cap)
	print("TEXCAP %s height=%.2f m, %d texture slot(s) on %d texture(s) capped at %d" % [tag, h, _swaps.size(), _count_textures(), cap])
	if _swaps.is_empty():
		print("TEXCAP nothing to cap: no texture in those slots is larger than ", cap)
		get_tree().quit()
		return

	var cam := Camera3D.new()
	add_child(cam)
	var focus := Vector3(0, h * 0.5, 0)
	for dist in dists:
		for view in VIEWS:
			var dir: Vector3 = (view[1] as Vector3).normalized()
			cam.global_position = focus + dir * (h * 0.95 * float(dist))
			cam.global_position.y = h * 0.55
			cam.look_at(focus, Vector3.UP)
			for variant in ["o", "a", "b", "a2"]:
				_apply(variant)
				await _settle()
				var img := get_viewport().get_texture().get_image()
				img.save_png(_abs("%s/%s_x%s_%s_%s.png" % [_out, tag, str(dist).trim_suffix(".0"), view[0], variant]))
	print("TEXCAP saved %d frames to %s" % [dists.size() * VIEWS.size() * 4, _out])
	get_tree().quit()

func _abs(path: String) -> String:
	return path if path.is_absolute_path() else ProjectSettings.globalize_path("res://" + path)

## Native scale and no temporal filter, re-applied every frame: GraphicsSettings
## sets the viewport from its tier after boot.
func _settle() -> void:
	for i in SETTLE_FRAMES:
		var vp := get_viewport()
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0
		vp.use_taa = false
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

## "o" the textures as imported, "b" capped, anything else rebuilt at full size.
func _apply(variant: String) -> void:
	for s in _swaps:
		(s[0] as BaseMaterial3D).set(s[1], s[4] if variant == "o" else (s[3] if variant == "b" else s[2]))

func _count_textures() -> int:
	var seen := {}
	for s in _swaps:
		seen[s[2]] = true
	return seen.size()

func _build_swaps(model: Node, cap: int) -> void:
	var full_of := {}    # source texture -> rebuilt full-size texture
	var capped_of := {}
	for mi in _all_meshes(model):
		for si in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(si) as BaseMaterial3D
			if mat == null:
				continue
			for slot in _slots:
				if not slot in mat:
					continue
				var tex := mat.get(slot) as Texture2D
				if tex == null or maxi(tex.get_width(), tex.get_height()) <= cap:
					continue
				if not full_of.has(tex):
					full_of[tex] = _rebuild(tex, 0)
					capped_of[tex] = _rebuild(tex, cap)
				_swaps.append([mat, slot, full_of[tex], capped_of[tex], tex])

## Both variants start from the source picture when the texture has one on disk,
## so neither carries block compression. A texture embedded in a GLB has no file:
## that one is decompressed from the import. Frame `o` (the import as it ships)
## is there to show the full-size rebuild stands in for it.
func _rebuild(tex: Texture2D, cap: int) -> ImageTexture:
	var img: Image = null
	var src := tex.resource_path
	if src.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "tga", "bmp"] and FileAccess.file_exists(src):
		img = Image.load_from_file(ProjectSettings.globalize_path(src))
	if img == null:
		img = tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	if cap > 0:
		var s := float(cap) / maxi(img.get_width(), img.get_height())
		img.resize(maxi(roundi(img.get_width() * s), 1), maxi(roundi(img.get_height() * s), 1), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _merged_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in _all_meshes(root):
		var ab: AABB = root.global_transform.affine_inverse() * (mi.global_transform * mi.get_aabb())
		if first:
			out = ab
			first = false
		else:
			out = out.merge(ab)
	return out

func _all_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).mesh != null:
			out.append(n)
	return out
