extends Node3D
## Focused repro: spawn the REAL player scene + a real raptor right next to each
## other and force an immediate attack, to check whether an enemy projectile
## hitting the player's Damageable throws the "Cannot convert argument 2 from
## Object to Object" signal error seen once in tools/balance_probe.tscn.
## Run: godot --headless --path . --quit-after 600 res://tests/enemy_proj_hit_probe.tscn

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const RAPTOR_SCENE := preload("res://scenes/enemies/raptor.tscn")

func _ready() -> void:
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	nav.add_child(floor_mi)
	var floor_body := StaticBody3D.new(); floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new(); var fbs := BoxShape3D.new(); fbs.size = Vector3(40, 1, 40)
	fcs.shape = fbs; fcs.position = Vector3(0, -0.5, 0); floor_body.add_child(fcs)
	nav.add_child(floor_body)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nm.agent_radius = 0.5; nm.cell_size = 0.25
	nav.navigation_mesh = nm; nav.bake_navigation_mesh()
	var sun := DirectionalLight3D.new(); add_child(sun)

	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	await get_tree().create_timer(0.3).timeout

	var raptor: Node3D = RAPTOR_SCENE.instantiate()
	add_child(raptor)
	raptor.global_position = Vector3(0, 3, -8)
	raptor.rotation.y = PI
	await get_tree().physics_frame
	if raptor.has_method("set_state"):
		raptor.target = player
		raptor.set_state(raptor.State.CHASE)

	var pdmg := player.get_node("Damageable") as Damageable
	var hp0 := pdmg.current_health
	var elapsed := 0.0
	while elapsed < 9.0:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()

	print("RESULT player_hp=%.0f/%.0f (dealt=%.0f)" % [pdmg.current_health, pdmg.max_health, hp0 - pdmg.current_health])
	print("ENEMY_PROJ_HIT_PROBE_DONE")
	get_tree().quit()
