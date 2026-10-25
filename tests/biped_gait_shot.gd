extends Node3D
## Windowed visual check for a static biped's walk (BipedGait): side and
## front-left views standing and at four points of its gait at full swing.
## Headless gives black frames.
##   godot --path . res://tests/biped_gait_shot.tscn -- --out=<abs dir> [--enemy=enforcer|gunslinger]

var _out_dir := ""
var _enemy := "enforcer"
var _e: CharacterBody3D
var _cam: Camera3D

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://biped_gait_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
		elif a.begins_with("--enemy="):
			_enemy = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(960, 540)
	img.save_png("%s/%s_%s.png" % [_out_dir, _enemy, name])
	print("SHOT ", name)

func _aim(from: Vector3, at: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)

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
	_e = (load("res://scenes/enemies/%s.tscn" % _enemy) as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 0.05, 0)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()
	for i in 12:
		await get_tree().physics_frame
	_e.set_physics_process(false)
	var gait = _e.get("_gait")
	for ph in [["stand", 0.0, 0.0], ["q0", 0.0, 1.0], ["q1", PI * 0.5, 1.0], ["q2", PI, 1.0], ["q3", PI * 1.5, 1.0]]:
		if gait:
			gait.pose_at(float(ph[1]), float(ph[2]))
		await get_tree().physics_frame
		_aim(Vector3(3.2, 1.1, 0.0), Vector3(0, 0.9, 0))
		await _shot(String(ph[0]) + "_side")
		_aim(Vector3(2.2, 1.4, -2.4), Vector3(0, 0.9, 0))
		await _shot(String(ph[0]) + "_front")
	get_tree().quit()
