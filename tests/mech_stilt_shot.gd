extends Node3D
## Windowed visual check for the stilt MECH: side view of a palm-bolt shot from
## range, then the leap: crouch (ground warning on the floor), apex, landing.
## Headless gives black frames.
##   godot --path . res://tests/mech_stilt_shot.tscn -- --out=<abs dir>

var _out_dir := ""

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://mech_stilt_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/mech_%s.png" % [_out_dir, name])
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

	var mech: EnemyMech = (load("res://scenes/enemies/mech.tscn") as PackedScene).instantiate()
	nav.add_child(mech)
	mech.global_position = Vector3(0, 0.2, -15.0)
	mech.rotation.y = PI # face the player, or it never sees it and idles
	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(12, 2.6, -8), Vector3(0, 1.7, -8))
	cam.current = true
	for i in 30:
		await get_tree().physics_frame
	mech.target = player
	mech.set_state(EnemyBase.State.CHASE)

	for i in 420: # a palm burst from range
		await get_tree().physics_frame
		if mech.recoil > 0.9 and not mech.is_leaping():
			for k in 4:
				await get_tree().physics_frame
			await _shot("shoot")
			break
	mech.global_position = Vector3(0, 0.0, -8.0)
	mech.velocity = Vector3.ZERO
	mech._attack_timer = 9.0
	var got := {}
	for i in 300:
		await get_tree().physics_frame
		if mech._leap == EnemyMech.Leap.WINDUP and mech._leap_t > 0.3 and not got.has("crouch"):
			got["crouch"] = true
			await _shot("crouch")
		elif mech._leap == EnemyMech.Leap.AIR and mech.velocity.y < 0.5 and not got.has("apex"):
			got["apex"] = true
			await _shot("apex")
		elif mech._leap == EnemyMech.Leap.RECOVER and mech._leap_t > 0.05 and not got.has("land"):
			got["land"] = true
			await _shot("land")
			break
	get_tree().quit()
