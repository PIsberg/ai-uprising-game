extends Node3D
## Windowed visual check for RAZORFIN's tail cut: top-down and side views
## with the tail straight and swung 0.45 rad to each side, to see the hinge
## sits at the peduncle and nothing else moves. Headless gives black frames.
##   godot --path . res://tests/shark_tail_shot.tscn -- --out=<abs dir>

var _out_dir := ""
var _e: CharacterBody3D
var _cam: Camera3D

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://shark_tail_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(960, 540)
	img.save_png("%s/shark_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _aim(from: Vector3, at: Vector3, up: Vector3 = Vector3.UP) -> void:
	_cam.global_position = from
	_cam.look_at(at, up)

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.28, 0.32)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.5
	add_child(sun)
	_e = (load("res://scenes/enemies/shark.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 3, 0)
	_e.set("move_speed", 0.0)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()
	for i in 12:
		await get_tree().physics_frame
	_e.set_physics_process(false)
	for pose in [["straight", 0.0], ["left", 0.45], ["right", -0.45]]:
		var tail: Array = _e.get("_tail_e")
		if not tail.is_empty():
			PartRig.pose(tail, PartRig.turn(_e.get("_tail_pivot"), Vector3.UP, float(pose[1])))
		_aim(Vector3(0.0, 8.0, 0.2), Vector3(0, 3, 0.2), Vector3.FORWARD)
		await _shot(String(pose[0]) + "_top")
		_aim(Vector3(5.0, 3.8, 0.3), Vector3(0, 3, 0.3))
		await _shot(String(pose[0]) + "_side")
	get_tree().quit()
