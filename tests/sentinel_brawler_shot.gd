extends Node3D
## Windowed visual check for the SENTINEL: side view of a throw leaving its
## right fist from range, then a punch wind-up and the hit up close.
## Headless gives black frames.
##   godot --path . res://tests/sentinel_brawler_shot.tscn -- --out=<abs dir>

var _out_dir := ""

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://sentinel_brawler_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/sentinel_%s.png" % [_out_dir, name])
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

	var sen: EnemySentinel = (load("res://scenes/enemies/sentinel.tscn") as PackedScene).instantiate()
	nav.add_child(sen)
	sen.global_position = Vector3(0, 0.2, -12.0)
	sen.rotation.y = PI # face the player, or it never sees it and idles
	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(15, 2.6, -6), Vector3(0, 1.4, -6))
	cam.current = true
	for i in 30:
		await get_tree().physics_frame
	sen.target = player
	sen.set_state(EnemyBase.State.CHASE)

	for i in 600: # a throw, caught as it leaves the fist
		await get_tree().physics_frame
		if sen._throw_t > 0.0 and sen._throw_t < 0.04:
			await get_tree().physics_frame
			await _shot("throw")
			break
	sen.global_position = Vector3(0, 0.0, -2.4)
	sen.velocity = Vector3.ZERO
	sen._attack_timer = 9.0
	var wound := false
	for i in 300:
		await get_tree().physics_frame
		if sen.is_punching() and sen._punch_t < 0.25 and not wound:
			wound = true
			await _shot("windup")
		elif wound and not sen.is_punching():
			await _shot("hit")
			break
	get_tree().quit()
