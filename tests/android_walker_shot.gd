extends Node3D
## Windowed visual check for the ANDROID (Quaternius "Leela"): side view of a
## shot leaving its face lens, a side-hop juke at its peak, then the kick
## wind-up and the claw landing up close.
## Headless gives black frames.
##   godot --path . res://tests/android_walker_shot.tscn -- --out=<abs dir>

var _out_dir := ""

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://android_walker_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/android_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _run() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.23, 0.28)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.66)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 40, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(90, 90)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.36, 0.37, 0.4)
	pm.material = fm
	fmi.mesh = pm
	nav.add_child(fmi)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(90, 1, 90)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	sb.add_child(cs)
	nav.add_child(sb)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nm.agent_radius = 0.5
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh()

	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	player.collision_mask = 1
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.7
	pcs.shape = cap
	pcs.position = Vector3(0, 0.9, 0)
	player.add_child(pcs)
	var pvis := MeshInstance3D.new()
	var pcm := CapsuleMesh.new()
	pcm.radius = 0.4
	pcm.height = 1.7
	pvis.mesh = pcm
	pvis.position = Vector3(0, 0.9, 0)
	player.add_child(pvis)
	var pd := Damageable.new()
	pd.name = "Damageable"
	pd.max_health = 1.0e9
	player.add_child(pd)
	add_child(player)

	var an: EnemyAndroid = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	nav.add_child(an)
	an.global_position = Vector3(0, 0.2, -10.0)
	an.rotation.y = PI # face the player, or it never sees it and idles
	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(7, 1.8, -7), Vector3(0, 1.2, -9))
	cam.current = true
	for i in 30:
		await get_tree().physics_frame
	var floor_y := an.global_position.y
	an.target = player
	an.set_state(EnemyBase.State.ATTACK)

	var shot_done := false
	var hop_done := false
	for i in 900: # a shot leaving the lens, and a hop at its peak
		await get_tree().physics_frame
		an.global_position.z = clampf(an.global_position.z, -11.0, -8.0)
		if an.state != EnemyBase.State.ATTACK:
			an.set_state(EnemyBase.State.ATTACK)
		if not shot_done and an._burst_remaining > 0 and an._burst_remaining < an.burst_count:
			shot_done = true
			await _shot("lens")
		elif not hop_done and an.global_position.y - floor_y > 0.45 and an.velocity.y < 0.6:
			hop_done = true
			await _shot("hop")
		if shot_done and hop_done:
			break
	cam.look_at_from_position(Vector3(5, 1.6, -1.2), Vector3(0, 1.0, -1.2))
	an.global_position = Vector3(0, floor_y, -2.2)
	an.velocity = Vector3.ZERO
	an._attack_timer = 9.0
	an._burst_remaining = 0
	an._dodge_cd = 9.0
	var wound := false
	for i in 300:
		await get_tree().physics_frame
		if an._kick_t > 0.0 and an._kick_t < 0.16 and not wound:
			wound = true
			await _shot("windup")
		elif wound and an._kick_t <= 0.0:
			await get_tree().physics_frame
			await _shot("kick")
			break
	get_tree().quit()
