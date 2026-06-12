extends Node3D
## Dev probe: renders the grenade up close (frozen, core lit) and saves
## user://grenade_screenshot.png. Run windowed:
##   godot --path . res://tests/grenade_screenshot.tscn

func _ready() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0.25, 0.9, 0.55)
	add_child(cam)
	cam.look_at(Vector3(0, 0.75, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.13, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.68)
	e.ambient_light_energy = 0.8
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_hdr_threshold = 1.1
	env.environment = e
	add_child(env)
	var g := (load("res://scenes/weapons/grenade.tscn") as PackedScene).instantiate() as RigidBody3D
	g.freeze = true
	g.position = Vector3(0, 0.75, 0)
	g.rotation_degrees = Vector3(12, 30, -8)
	add_child(g)
	await get_tree().create_timer(0.35).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/grenade_screenshot.png")
	print("SAVED ", OS.get_user_data_dir() + "/grenade_screenshot.png")
	get_tree().quit()
