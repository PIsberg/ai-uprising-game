extends Node3D
## Windowed visual check for physics wrecks (WreckBody): four robots shot from
## the left, two on a 3 m catwalk at its edge, two on the floor; shot mid-fall
## and at rest, to see the chassis lies on the floor rather than in or above it.
## Headless gives black frames.
##   godot --path . res://tests/wreck_shot.tscn -- --out=<abs dir>

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://wreck_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.45)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	_box(Vector3(80, 1, 80), Vector3(0, -0.5, 0), Color(0.16, 0.17, 0.19))
	_box(Vector3(8, 0.4, 4), Vector3(-4, 2.8, -3), Color(0.25, 0.27, 0.3)) # catwalk, edge at x = 0
	var cam := Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	cam.global_position = Vector3(3.0, 4.2, 9.5)
	cam.look_at(Vector3(0.5, 1.2, -1.5), Vector3.UP)
	cam.current = true
	var player := Node3D.new()
	player.add_to_group("player")
	add_child(player)
	player.global_position = Vector3(0, 0, 80) # out of sight: no AI
	var shooter := Node3D.new()
	add_child(shooter)
	shooter.global_position = Vector3(-12, 3.5, 0)
	var bots: Array = []
	var spots := [["gunner", Vector3(-0.5, 3.0, -2.2)], ["reaper", Vector3(-0.5, 3.0, -4.0)],
		["mech", Vector3(-2.5, 0.0, 1.5)], ["hunter", Vector3(-4.5, 0.0, 2.5)]]
	for s in spots:
		var e: EnemyBase = (load("res://scenes/enemies/%s.tscn" % s[0]) as PackedScene).instantiate()
		add_child(e)
		e.global_position = s[1]
		bots.append(e)
	await _physics(45)
	for i in bots.size():
		var e: EnemyBase = bots[i]
		e.set_physics_process(false)
		e.global_position = spots[i][1]
		e.look_at(e.global_position + Vector3.LEFT, Vector3.UP) # facing the shooter
		e._last_known_target_pos = shooter.global_position
		e._has_last_known = true
	await _physics(20)
	await _snap(out_dir, "wreck_0_standing")
	for e in bots:
		e.hp.apply_damage(99999.0, shooter)
	await _physics(24)
	await _snap(out_dir, "wreck_1_falling")
	await _physics(48)
	await _snap(out_dir, "wreck_2_rest")
	print("RESULT PASS")
	get_tree().quit()

func _box(size: Vector3, pos: Vector3, col: Color) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	bm.material = m
	mi.mesh = bm
	b.add_child(mi)
	add_child(b)
	b.global_position = pos

func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _snap(dir: String, stem: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(stem + ".png"))
