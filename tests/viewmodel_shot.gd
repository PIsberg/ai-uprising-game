extends Node3D
## Windowed look-check of every gun in the player's hands, in a real level: for
## each gun in GameState.WEAPON_ORDER, then each Salvage.TABLE gun, one frame at rest (<id>_idle.png), one
## at the kick's peak with its muzzle flash (<id>_fire.png) and one 40% into a
## reload (<id>_reload.png), plus a contact sheet of the fire frames
## (viewmodels.png). Headless renders black.
##   godot --path . res://tests/viewmodel_shot.tscn -- --out=<abs dir> [--level=res://scenes/levels/level_gpt.tscn] [--only=rifle,omega]

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var out_dir := ProjectSettings.globalize_path("user://viewmodel_shots")
	var level := "res://scenes/levels/level_gpt.tscn"
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--level="):
			level = a.substr(8)
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	add_child((load(level) as PackedScene).instantiate())
	for i in 60:
		await get_tree().physics_frame
	GameState.set_state(GameState.State.PLAYING)
	# Robots off: nothing walks into frame or shoots the camera.
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
	# Let the level-start overlord broadcast (and its screen glitch) play out.
	await get_tree().create_timer(4.0).timeout
	var player := get_tree().get_first_node_in_group("player") as Node3D
	player.set_physics_process(false)
	# Splash guns (Devastator, OMEGA) fired at the floor would otherwise kill the
	# camera, and every later gun was shot on the red, rolled death view.
	(player.get_node("Damageable") as Damageable).invulnerable = true
	var cam := player.get_node("Head/Camera3D") as Camera3D
	var wm: Node = player.get_node("Head/Camera3D/WeaponHolder")
	var tiles: Array[Image] = []
	var guns: Array = GameState.WEAPON_ORDER.duplicate()
	for k in Salvage.TABLE:
		guns.append(String(Salvage.TABLE[k]["scene"]))
	for p: String in guns:
		var id := p.get_file().get_basename()
		if not only.is_empty() and not id in only:
			continue
		wm.add_weapon(load(p), false)
		for i in wm.weapons.size():
			if (wm.weapons[i] as Weapon).scene_file_path == p:
				wm._equip(i)
		await get_tree().create_timer(0.9).timeout # draw time + settle
		var idle := await _grab()
		idle.save_png(out_dir.path_join(id + "_idle.png"))
		var w: Weapon = wm.current
		w.mag = maxi(w.mag, 3)
		w._cooldown = 0.0
		w._fire_once(cam, player, false)
		await get_tree().create_timer(0.045).timeout # near the kick's peak
		var fire := await _grab()
		fire.save_png(out_dir.path_join(id + "_fire.png"))
		var tile := fire.duplicate() as Image
		tile.resize(426, 240)
		tiles.append(tile)
		await get_tree().create_timer(0.8).timeout
		# Mid-reload, 40% in: the style's pose with its first beats played.
		w.mag = 0
		w.reserve = maxi(w.reserve, w.eff_mag_size())
		w.start_reload()
		await get_tree().create_timer(maxf(0.6, w.eff_reload_time()) * 0.4).timeout
		(await _grab()).save_png(out_dir.path_join(id + "_reload.png"))
		await get_tree().create_timer(maxf(0.6, w.eff_reload_time()) * 0.7).timeout
		print("captured ", id)
	if not tiles.is_empty():
		var cols := 4
		var rows := ceili(tiles.size() / float(cols))
		var sheet := Image.create(426 * cols, 240 * rows, false, tiles[0].get_format())
		for i in tiles.size():
			sheet.blit_rect(tiles[i], Rect2i(0, 0, 426, 240), Vector2i((i % cols) * 426, (i / cols) * 240))
		sheet.save_png(out_dir.path_join("viewmodels.png"))
	print("RESULT PASS")
	get_tree().quit()

func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()
