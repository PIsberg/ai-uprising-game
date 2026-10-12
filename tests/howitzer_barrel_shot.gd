extends Node3D
## Windowed visual check for the HOWITZER's laid barrel: side view at rest, at
## full elevation (+20 deg), fully dipped (-12 deg) and at full recoil.
## Headless gives black frames.
##   godot --path . res://tests/howitzer_barrel_shot.tscn -- --out=<abs dir>

var _out_dir := ""

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://howitzer_barrel_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/howitzer_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _run() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.23, 0.28)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.66)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 40, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(4.2, 2.9, -0.6)
	cam.look_at(Vector3(0, 2.8, -0.6))
	cam.current = true
	var e: Node3D = (load("res://scenes/enemies/howitzer.tscn") as PackedScene).instantiate()
	add_child(e)
	for i in 8:
		await get_tree().physics_frame
	e.set_physics_process(false)
	for pose in [["rest", 0.0, 0.0], ["up20", 0.35, 0.0], ["down12", -0.21, 0.0], ["kick", 0.1, 0.5]]:
		e.set("elevation", pose[1])
		e.set("_kick", pose[2])
		e.call("_lay_gun", 0.0)
		await get_tree().process_frame
		await _shot(pose[0])
	print("RESULT PASS")
	get_tree().quit()
