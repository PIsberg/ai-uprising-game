extends Node3D
## Windowed look-check of the hands holding every gun, in a neutral studio (no
## level lighting or HUD in the way): per gun one tile from the player's eye
## (WeaponHolder offset, fov 78) and one side view from the near (left) side,
## plus <out>/hands.png, a contact sheet of every pair. Headless renders black.
##   godot --path . res://tools/hands_shot.tscn -- --out=<abs dir> [--only=rifle,pistol]

const EYE := Vector3(-0.25, 0.22, 0.45) ## the camera, in viewmodel space (player.tscn WeaponHolder)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var out_dir := ProjectSettings.globalize_path("user://hands_shots")
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_studio()
	var cam := Camera3D.new()
	cam.near = 0.02
	add_child(cam)
	cam.make_current()
	var guns: Array = GameState.WEAPON_ORDER.duplicate()
	for k in Salvage.TABLE:
		guns.append(String(Salvage.TABLE[k]["scene"]))
	var tiles: Array[Image] = []
	for p: String in guns:
		var id := p.get_file().get_basename()
		if not only.is_empty() and not id in only:
			continue
		var w := (load(p) as PackedScene).instantiate() as Node3D
		add_child(w)
		w.set_process(false)
		for i in 4:
			await get_tree().process_frame
		cam.fov = 78.0
		cam.look_at_from_position(EYE, EYE + Vector3.FORWARD, Vector3.UP)
		var eye := await _grab()
		eye.save_png(out_dir.path_join(id + "_eye.png"))
		cam.fov = 40.0
		cam.look_at_from_position(Vector3(-1.6, 0.05, -0.15), Vector3(0, -0.05, -0.15), Vector3.UP)
		var side := await _grab()
		side.save_png(out_dir.path_join(id + "_side.png"))
		for im in [eye, side]:
			var t := (im as Image).duplicate() as Image
			t.convert(Image.FORMAT_RGBA8)
			t.resize(480, 300)
			tiles.append(t)
		w.queue_free()
		await get_tree().process_frame
	var cols := 4
	var rows := ceili(tiles.size() / float(cols))
	var sheet := Image.create(480 * cols, 300 * maxi(1, rows), false, Image.FORMAT_RGBA8)
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, 480, 300), Vector2i((i % cols) * 480, (i / cols) * 300))
	sheet.save_png(out_dir.path_join("hands.png"))
	print("HANDS SHOTS ", out_dir)
	get_tree().quit()

func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

## Grey studio: soft sky ambient, a key light from over the right shoulder.
func _studio() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.4, 0.48)
	sky_mat.sky_horizon_color = Color(0.6, 0.62, 0.66)
	sky_mat.ground_bottom_color = Color(0.16, 0.16, 0.18)
	sky_mat.ground_horizon_color = Color(0.42, 0.43, 0.46)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 30, 0)
	key.light_energy = 1.4
	add_child(key)
