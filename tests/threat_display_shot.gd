extends Node3D
## Windowed visual check for the threat display: an ANDROID, a DOG and a
## DRONE from the side, at rest and at the top of the bristle (chassis
## reared back and lifted). Headless gives black frames.
##   godot --path . res://tests/threat_display_shot.tscn -- --out=<abs dir>

var _out_dir := ""
var _cam: Camera3D

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://threat_display_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(960, 540)
	img.save_png("%s/threat_%s.png" % [_out_dir, name])
	print("SHOT ", name)

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
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()
	for spec in [["android", 0.05, 0.9], ["dog", 0.05, 0.6], ["drone", 2.0, 2.0]]:
		var e: CharacterBody3D = (load("res://scenes/enemies/%s.tscn" % spec[0]) as PackedScene).instantiate()
		add_child(e)
		e.global_position = Vector3(0, float(spec[1]), 0)
		e.set("sight_range", 0.0)
		for i in 12:
			await get_tree().physics_frame
		e.set_physics_process(false)
		_cam.global_position = Vector3(3.4, float(spec[2]) + 0.5, 0.0)
		_cam.look_at(Vector3(0, float(spec[2]), 0), Vector3.UP)
		await _shot(String(spec[0]) + "_rest")
		e.set("_bristle", 0.5)
		e.call("_update_hit_react", 0.0)
		await get_tree().physics_frame
		await _shot(String(spec[0]) + "_bristle")
		e.queue_free()
		await get_tree().physics_frame
	get_tree().quit()
