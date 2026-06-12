extends Node3D
## Dev probe: builds a SkyTraffic system, forces a few meteors, and captures
## a sky view to user://sky_screenshot.png. Run windowed:
##   godot --path . res://tests/sky_screenshot.tscn

func _ready() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 2, 0)
	cam.rotation_degrees = Vector3(18, 0, 0) # look up at the traffic lanes
	add_child(cam)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.04, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.45, 0.6)
	e.ambient_light_energy = 0.7
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_hdr_threshold = 1.1
	env.environment = e
	add_child(env)
	var traffic := SkyTraffic.new()
	traffic.arena_radius = 10.0 # pull the lanes close so the probe can see hulls
	add_child(traffic)
	await get_tree().create_timer(0.5).timeout
	for i in 3:
		traffic.spawn_meteor()
	await get_tree().create_timer(0.45).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/sky_screenshot.png")
	print("SAVED ", OS.get_user_data_dir() + "/sky_screenshot.png")
	get_tree().quit()
