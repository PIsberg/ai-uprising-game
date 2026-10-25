extends Node3D
## Windowed visual check for the ROLLER's rig: front-left view at rest, in the
## ram's plant (drum reared, arms cocked, wheel spinning up) and in the charge
## (drum tipped in, arms lashed forward), plus the wheel alone at rest and a
## quarter turn on, to see that nothing static spins with it.
## Headless gives black frames.
##   godot --path . res://tests/roller_rig_shot.tscn -- --out=<abs dir>

var _out_dir := ""
var _e: CharacterBody3D
var _cam: Camera3D

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://breaker_hammer_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(960, 540)
	img.save_png("%s/breaker_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _aim(from: Vector3, at: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)

func _hold(swing_t: float, frames: int) -> void:
	for i in frames:
		_e.set("_swing_t", swing_t)
		await get_tree().physics_frame

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.28, 0.32)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.6
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	add_child(floor_mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	_e = (load("res://scenes/enemies/breaker.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 1.6, 0)
	_e.set("move_speed", 0.0)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()
	for i in 12:
		await get_tree().physics_frame
	for pose in [["hang", -1.0], ["wind", 0.0], ["strike", EnemyBreaker.WIND_T]]:
		await _hold(float(pose[1]), 30)
		_aim(Vector3(-3.0, 1.9, 0.0), Vector3(0, 1.6, 0))
		await _shot(String(pose[0]) + "_side")
		_aim(Vector3(-2.2, 2.3, -2.6), Vector3(0, 1.6, 0))
		await _shot(String(pose[0]) + "_front")
	get_tree().quit()
