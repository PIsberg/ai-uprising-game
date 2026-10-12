extends Node3D
## Windowed visual check for the ENFORCER's rifle: front-right and top-down
## views at port arms, shouldered onto a mark 10 m ahead, and onto one up on a
## ledge.
## Headless gives black frames.
##   godot --path . res://tests/enforcer_rifle_shot.tscn -- --out=<abs dir>

var _out_dir := ""

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://enforcer_rifle_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

var _cam: Camera3D

## The pose from the front-right, then from above.
func _shot(name: String) -> void:
	for view in [["", Vector3(2.6, 1.6, -3.2)], ["_top", Vector3(0.01, 4.5, -0.3)]]:
		_cam.position = view[1]
		_cam.look_at(Vector3(0, 1.15, -0.2))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/enforcer_%s%s.png" % [_out_dir, name, view[0]])
	print("SHOT ", name)

func _run() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.35, 0.4)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.9, 0.95)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 150, 0)
	add_child(sun)
	var e: Node3D = (load("res://scenes/enemies/enforcer.tscn") as PackedScene).instantiate()
	add_child(e)
	for i in 6:
		await get_tree().physics_frame
	e.set_physics_process(false) # driven by hand below
	e.call("_tick_rifle", 0.0)    # measures the rifle once the fit has landed
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	_cam.fov = 40.0
	await get_tree().process_frame
	await _shot("port_arms")
	var mark := Node3D.new()
	add_child(mark)
	mark.position = Vector3(0, 0.6, -10)
	e.set("target", mark)
	e.set("state", 4) # ATTACK, without the state machine's side effects
	for i in 30:
		e.call("_tick_rifle", 1.0 / 60.0)
	await get_tree().process_frame
	await _shot("shouldered")
	mark.position = Vector3(-3, 5.0, -8)
	for i in 30:
		e.call("_tick_rifle", 1.0 / 60.0)
	await get_tree().process_frame
	await _shot("ledge")
	print("RESULT PASS")
	get_tree().quit()
