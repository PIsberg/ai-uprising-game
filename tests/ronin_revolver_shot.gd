extends Node3D
## Windowed visual check for the RONIN: front view (face, katana on its back),
## then its right side as each revolver quick-draws onto a mark ahead of it,
## up and back down. Headless gives black frames.
##   godot --path . res://tests/ronin_revolver_shot.tscn -- --out=<abs dir>

var _out_dir := ""

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://ronin_revolver_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/ronin_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _run() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.33, 0.38)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.9)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 150, 0)
	add_child(sun)
	var mark := Node3D.new()
	add_child(mark)
	mark.position = Vector3(0, 0.6, -8.0)
	var e: Node3D = (load("res://scenes/enemies/ronin.tscn") as PackedScene).instantiate()
	add_child(e)
	for i in 6:
		await get_tree().physics_frame
	e.set_physics_process(false) # driven by hand below
	for i in 3:
		e.call("_tick_guns", 0.0)  # splits the guns once the fit has landed
		await get_tree().physics_frame
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 40.0
	cam.position = Vector3(0, 1.4, -4.5)
	cam.look_at(Vector3(0, 1.15, 0))
	await _shot("front")
	cam.position = Vector3(4.5, 1.2, -0.6)
	cam.look_at(Vector3(0, 0.9, -0.6))
	e.set("target", mark)
	for k in 2:
		e.call("_fire_slug")
		for step in 4:
			e.call("_tick_guns", 0.05 if step == 0 else 0.1)
			await get_tree().process_frame
			if step == 1:
				await _shot("draw_%d" % k)
		e.call("_tick_guns", 0.5)
		e.set("_slug_cd", 0.0)
	await _shot("holstered")
	print("RESULT PASS")
	get_tree().quit()
