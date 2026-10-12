extends Node3D
## Windowed visual check for the K-9 HUNTER's trot: side view at four points
## of the gait cycle at a run, then the stretched pounce pose in the air.
## Headless gives black frames.
##   godot --path . res://tests/dog_gait_shot.tscn -- --out=<abs dir>

var _out_dir := ""

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://dog_gait_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/dog_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _run() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.28, 0.32)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 60, 0)
	add_child(sun)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	var e: CharacterBody3D = (load("res://scenes/enemies/dog.tscn") as PackedScene).instantiate()
	add_child(e)
	for i in 10:
		await get_tree().physics_frame # lands, fits, splits its legs
	e.set_physics_process(false)    # the gait is driven by hand below
	e.get_node("Model").set_physics_process(false)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 40.0
	cam.position = Vector3(3.2, 0.7, 0)
	cam.look_at(Vector3(0, 0.45, 0))
	e.velocity = Vector3(0, 0, -6.0)
	for k in 4:
		for i in 6:
			e.call("_tick_gait", 1.0 / 60.0)
		await get_tree().process_frame
		await _shot("trot_%d" % k)
	e.set("_air_w", 1.0)
	e.set("_gait_amp", 0.0)
	e.call("_tick_gait", 0.0)
	await get_tree().process_frame
	await _shot("air")
	print("RESULT PASS")
	get_tree().quit()
