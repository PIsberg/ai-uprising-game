extends Node3D
## Windowed: photographs a pack of four K-9 HUNTERs on a stand-in player (the
## white post) from above, PACK HUNT on. Two frames into user://: one dog
## rearing while the other three run the ring (dog_pack_rear.png), and one in
## the air (dog_pack_air.png).
##   godot --path . res://tests/dog_pack_shot.tscn

func _ready() -> void:
	GameState.set_state(GameState.State.PLAYING)
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	fmi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.34, 0.38)
	fmi.material_override = fm
	nav.add_child(fmi)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(60, 1, 60)
	fcs.shape = fbox
	fcs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fcs)
	nav.add_child(floor_body)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nm.agent_radius = 0.5
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.09, 0.11)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.65, 0.7)
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	player.collision_mask = 0
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	pcs.shape = cap
	pcs.position.y = 0.9
	player.add_child(pcs)
	var post := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 1.8
	post.mesh = cm
	post.position.y = 0.9
	player.add_child(post)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 100000.0
	player.add_child(hp)
	add_child(player)
	hp.current_health = 100000.0
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 13, 10)
	cam.look_at(Vector3(0, 0.5, 0))
	cam.make_current()
	for i in 10:
		await get_tree().physics_frame
	var pack: Array = []
	for o: Vector3 in [Vector3(8, 0, 0), Vector3(-8, 0, 0), Vector3(0, 0, 8), Vector3(0, 0, -8)]:
		var d: EnemyBase = (load("res://scenes/enemies/dog.tscn") as PackedScene).instantiate()
		add_child(d)
		d.global_position = o + Vector3.UP * 0.3
		pack.append(d)
	for i in 3:
		await get_tree().physics_frame
	for d: EnemyBase in pack:
		d.target = player
		d.set_state(EnemyBase.State.CHASE)
	# Let the hunt settle, then catch a rear and a flight.
	for i in 240:
		await get_tree().physics_frame
	await _when(pack, func(d: Node) -> bool: return float(d.get("_pounce_windup_t")) > 0.0 and float(d.get("_pounce_windup_t")) < 0.2)
	await _snap("dog_pack_rear")
	await _when(pack, func(d: Node) -> bool: return bool(d.get("_pouncing")) and d.global_position.y > 0.9)
	await _snap("dog_pack_air")
	print("DOG_PACK_SHOT_DONE")
	get_tree().quit()

func _when(pack: Array, test: Callable) -> void:
	for i in 600:
		await get_tree().physics_frame
		for d in pack:
			if is_instance_valid(d) and test.call(d):
				return

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/%s.png" % name)
