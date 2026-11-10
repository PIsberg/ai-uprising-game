extends Node3D
## Visual check: does the BRUTE still visibly carry its frontal shield slab?
## Captures front and three-quarter shots to user://brute_shield_*.png.
##   godot --path . res://tests/brute_shield_probe.tscn

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.12)
	e.glow_enabled = true
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.65)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	var bot: Node3D = load("res://scenes/enemies/brute.tscn").instantiate()
	add_child(bot)
	bot.set_physics_process(false)
	var cam := Camera3D.new()
	add_child(cam)
	_run.call_deferred(bot, cam)

func _run(bot: Node3D, cam: Camera3D) -> void:
	var out_dir := OS.get_user_data_dir()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().create_timer(0.5).timeout
	var brute := bot as EnemyBrute
	cam.global_position = Vector3(-1.4, 1.7, -5.0)
	cam.look_at(Vector3(0, 1.2, 0), Vector3.UP)
	await _shot(out_dir.path_join("brute_rush_closed.png"))
	brute._set_shield_glow(1.0, 9.0)
	await _shot(out_dir.path_join("brute_rush_tell.png"))
	brute._hang_open(EnemyBrute.RUSH_STUN)
	brute._set_shield_glow(0.05, 0.4)
	await _shot(out_dir.path_join("brute_rush_open.png"))
	print("RESULT PASS")
	get_tree().quit()

func _shot(path: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
