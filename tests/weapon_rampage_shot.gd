extends Node3D
## Windowed visual check for the RAMPAGE gun charge: the same rifle twice in
## front of the camera, left at tier 0 and right charged at tier 2 (red rim):
## one frame before firing, one with a muzzle flash each. Headless gives black frames.
##   godot --path . res://tests/weapon_rampage_shot.tscn -- --out=<abs dir>

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://weapon_rampage_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.42, 0.5)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 0.25 # dim: the rim must read on its own
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.global_position = Vector3(0, 0, 1.6)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.current = true
	var guns: Array[Weapon] = []
	for x in [-0.45, 0.45]:
		var w: Weapon = (load("res://scenes/weapons/rifle.tscn") as PackedScene).instantiate()
		add_child(w)
		w.global_position = Vector3(x, -0.05, 0)
		w.rotation.y = deg_to_rad(80.0)
		guns.append(w)
	await get_tree().process_frame
	GameState.rampage_tier = 2
	GameState.rampage_changed.emit(2, "UNSTOPPABLE")
	# Only the right gun keeps the charge: put the left one back.
	for mi in guns[0].rim_meshes():
		(mi as MeshInstance3D).material_overlay = null
	for i in 5:
		await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("weapon_rampage_idle.png"))
	GameState.rampage_tier = 0
	guns[0]._play_muzzle()
	GameState.rampage_tier = 2
	guns[1]._play_muzzle()
	await get_tree().create_timer(0.03).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("weapon_rampage_0.png"))
	GameState.rampage_tier = 0
	print("RESULT PASS")
	get_tree().quit()
