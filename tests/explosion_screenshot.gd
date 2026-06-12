extends Node3D
## Dev probe: detonates both explosion FX and captures the frame ~0.15s in
## (fireball + shockwave mid-expansion) to user://explosion_screenshot.png.
## Run windowed:  godot --path . res://tests/explosion_screenshot.tscn

func _ready() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 2.2, 7.0)
	cam.rotation_degrees = Vector3(-10, 0, 0)
	add_child(cam)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	e.ambient_light_energy = 0.6
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_hdr_threshold = 1.1
	env.environment = e
	add_child(env)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(24, 24)
	floor_mi.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.2, 0.21, 0.24)
	floor_mi.material_override = fmat
	add_child(floor_mi)
	# Let a few frames settle, then detonate and capture mid-expansion.
	await get_tree().create_timer(0.4).timeout
	for it in [["res://scenes/fx/enemy_explosion.tscn", Vector3(-2.5, 0.6, 0)],
			["res://scenes/fx/grenade_explosion.tscn", Vector3(2.5, 0.4, 0)]]:
		var fx := (load(it[0]) as PackedScene).instantiate() as Node3D
		add_child(fx)
		fx.global_position = it[1]
	await get_tree().create_timer(0.1).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/explosion_screenshot.png")
	print("SAVED ", OS.get_user_data_dir() + "/explosion_screenshot.png")
	get_tree().quit()
