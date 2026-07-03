extends Node3D
## Minimal repro: an ElectricBeam alone, viewed from the exact player pose,
## with the exact in-game endpoints (muzzle -> crosshair hit). Counts bright
## pixels programmatically. A control beam parked across the view runs second.
##   godot --path . res://tests/beam_axial_probe.tscn

func _ready() -> void:
	var cam := Camera3D.new()
	cam.fov = 78.0
	add_child(cam)
	cam.global_position = Vector3(0, 1.6, 0)
	var beam := ElectricBeam.new()
	add_child(beam)
	_run.call_deferred(beam)

func _run(beam: ElectricBeam) -> void:
	# Phase 1: axial (the real fire pose).
	for i in 12:
		beam.update_beam(Vector3(0.25, 1.40, -0.81), Vector3(0.12, 1.53, -7.5), false)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/beam_axial.png")
	print("axial bright_px=", _count_bright(img))
	# Phase 2: control, crossing the view.
	for i in 12:
		beam.update_beam(Vector3(-2.5, 1.2, -5.0), Vector3(2.5, 2.0, -5.0), false)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	img = get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/beam_cross.png")
	print("cross bright_px=", _count_bright(img))
	# Phase 3: axial WITH hit FX (impact flare/light/scorch path).
	for i in 12:
		beam.update_beam(Vector3(0.25, 1.40, -0.81), Vector3(0.12, 1.53, -7.5), true)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	img = get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/beam_axial_hit.png")
	print("axial_hit bright_px=", _count_bright(img))
	# Phase 4: same, plus the game-probe WorldEnvironment (glow, dark bg).
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.09)
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	for i in 12:
		beam.update_beam(Vector3(0.25, 1.40, -0.81), Vector3(0.12, 1.53, -7.5), true)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	img = get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/beam_axial_env.png")
	print("axial_env bright_px=", _count_bright(img))
	# Phase 5: add the PLAYER scene (idle, off to the side so its camera isn't
	# used — probe camera stays current). Does its mere presence kill the beam?
	var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector3(8, 0.5, 4)
	await get_tree().create_timer(0.4).timeout
	var cam0 := get_children().filter(func(c): return c is Camera3D)[0] as Camera3D
	cam0.current = true
	for i in 12:
		beam.update_beam(Vector3(0.25, 1.40, -0.81), Vector3(0.12, 1.53, -7.5), true)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	img = get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/beam_axial_player.png")
	print("axial_player bright_px=", _count_bright(img))
	# Phase 6: player parked AT the view position (gun viewmodel in front of the
	# probe camera, still not firing). Probe camera stays current.
	player.global_position = Vector3(0, 0.0, 0)
	await get_tree().create_timer(0.3).timeout
	cam0.current = true
	for i in 12:
		beam.update_beam(Vector3(0.25, 1.40, -0.81), Vector3(0.12, 1.53, -7.5), true)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	img = get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/beam_axial_vm.png")
	print("axial_vm bright_px=", _count_bright(img))
	# Phase 7: equip the TESLA on that player (its viewmodel + glow materials in
	# front of the camera), beam still driven manually.
	var wm = player.get_node("Head/Camera3D/WeaponHolder")
	wm.add_weapon(load("res://scenes/weapons/tesla.tscn"), true)
	await get_tree().create_timer(0.6).timeout
	cam0.current = true
	for i in 12:
		beam.update_beam(Vector3(0.25, 1.40, -0.81), Vector3(0.12, 1.53, -7.5), true)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	img = get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/beam_axial_tesla.png")
	print("axial_tesla bright_px=", _count_bright(img))
	# Phase 8: add the game-probe's floor + wall + sun. If the beam dies here,
	# the opaque geometry / directional light interaction is the killer.
	var sun := DirectionalLight3D.new()
	add_child(sun)
	var floor_body := StaticBody3D.new(); floor_body.collision_layer = 1
	var fmi := MeshInstance3D.new(); var fpm := PlaneMesh.new(); fpm.size = Vector2(60, 60)
	fmi.mesh = fpm; floor_body.add_child(fmi)
	add_child(floor_body)
	var wall := StaticBody3D.new(); wall.collision_layer = 1
	var wmi := MeshInstance3D.new(); var wbm := BoxMesh.new(); wbm.size = Vector3(10, 6, 1)
	wmi.mesh = wbm; wall.add_child(wmi)
	wall.position = Vector3(0, 3, -8)
	add_child(wall)
	for i in 12:
		beam.update_beam(Vector3(0.25, 1.40, -0.81), Vector3(0.12, 1.53, -7.5), true)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	img = get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/beam_axial_world.png")
	print("axial_world bright_px=", _count_bright(img))
	get_tree().quit()

func _count_bright(img: Image) -> int:
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			if c.b > 0.25 and c.b > c.r:
				n += 1
	return n
