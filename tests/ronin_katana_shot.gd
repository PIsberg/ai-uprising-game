extends Node3D
## Windowed visual check for the RONIN's katana, from its front-right: the
## sword drawn to its guard, raised over the shoulder in the wind-up, the
## middle of each cut with its slash trail, and sheathed again. Headless gives
## black frames.
##   godot --path . res://tests/ronin_katana_shot.tscn -- --out=<abs dir>

var _out_dir := ""
var _e: Node3D

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://ronin_katana_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/katana_%s.png" % [_out_dir, name])
	print("SHOT ", name)

## Advance the sword by hand for `t` seconds of physics time.
func _tick(t: float) -> void:
	var dt := 1.0 / 60.0
	var n := int(round(t / dt))
	for i in n:
		_e.call("_tick_sword", dt)
	await get_tree().process_frame

func _run() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.22, 0.24, 0.28)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 150, 0)
	add_child(sun)
	var mark := Node3D.new()
	add_child(mark)
	mark.position = Vector3(0, 0, -2.0)
	_e = (load("res://scenes/enemies/ronin.tscn") as PackedScene).instantiate()
	add_child(_e)
	for i in 6:
		await get_tree().physics_frame
	_e.set_physics_process(false) # driven by hand below
	await _tick(0.05)              # measures the sheathed sword once the fit has landed
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 45.0
	cam.position = Vector3(2.6, 1.6, -3.0)
	cam.look_at(Vector3(0, 1.2, -0.3))
	_e.set("target", mark)
	await _tick(0.6)
	await _shot("guard")
	_e.set("_telegraphing", true)
	await _tick(0.3)
	await _shot("windup")
	_e.set("_telegraphing", false)
	_e.set("_combo_t", 0.0)
	await _tick(0.07)
	await _shot("cut1")
	await _tick(0.18)
	await _shot("cut2")
	_e.set("target", null)
	await _tick(2.5)
	await _shot("sheathed")
	print("RESULT PASS")
	get_tree().quit()
