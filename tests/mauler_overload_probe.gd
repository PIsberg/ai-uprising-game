extends Node3D
## Verifies the MAULER's OVERLOAD "wounded mauler RUNS" sprint is actually applied.
## The bug: _begin_overload bumped _speed_mult (spent once at spawn in _sync_stats,
## never re-read) so the sprint was dead. Fixed to bump live move_speed.
## Expect: after HP drops below overload_at, move_speed ~1.7x its base and
## chase_speed() rises accordingly, and the sprint plays the model's Running
## clip (RobotExpressive), not its Walking clip pushed past its stride.
## Run: godot --headless --path . res://tests/mauler_overload_probe.tscn

func _ready() -> void:
	# A floor with a navmesh, or the charge below falls / has no path to run.
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	fmi.mesh = pm
	nav.add_child(fmi)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(80, 1, 80)
	fcs.shape = fbox
	fcs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fcs)
	nav.add_child(floor_body)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nm.agent_radius = 0.5
	nm.cell_size = 0.25
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh()
	for i in 10:
		await get_tree().physics_frame
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2 # a body its line of sight can land on
	var pcs := CollisionShape3D.new()
	var pcap := CapsuleShape3D.new()
	pcs.shape = pcap
	pcs.position = Vector3(0, 0.9, 0)
	player.add_child(pcs)
	var pdmg := Damageable.new(); pdmg.name = "Damageable"; pdmg.max_health = 9999.0
	pdmg.invulnerable = true; player.add_child(pdmg)
	add_child(player)
	player.global_position = Vector3(0, 0.05, 0)

	var m: EnemyMauler = (load("res://scenes/enemies/mauler.tscn") as PackedScene).instantiate()
	add_child(m)
	m.global_position = Vector3(0, 0.5, 12)
	await get_tree().process_frame
	await get_tree().physics_frame  # let _sync_stats (deferred) land

	m.target = player
	var base_speed: float = m.move_speed
	var base_chase: float = m.chase_speed()

	# Trip overload: drop health below overload_at (0.35).
	m.hp.current_health = m.hp.max_health * 0.20
	# One physics tick runs _physics_process -> _begin_overload.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var od_speed: float = m.move_speed
	var od_chase: float = m.chase_speed()
	var ratio: float = od_speed / maxf(base_speed, 0.01)
	print("MAULER base_speed=%.2f overload_speed=%.2f ratio=%.2f  base_chase=%.2f overload_chase=%.2f  overloading=%s" % [
		base_speed, od_speed, ratio, base_chase, od_chase, m._overloading])

	var ok := m._overloading and ratio > 1.6 and ratio < 1.8 and od_chase > base_chase * 1.5

	# The overload charge: frames at sprint speed, and how many play Running.
	m.set_state(EnemyBase.State.CHASE)
	var anim: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	var fast := 0
	var fast_run := 0
	for f in 50:
		await get_tree().physics_frame
		if not is_instance_valid(m) or m.state == EnemyBase.State.DEAD:
			break
		if Vector2(m.velocity.x, m.velocity.z).length() >= 6.5:
			fast += 1
			if anim.current_animation == "Running":
				fast_run += 1
	var runs := fast >= 15 and fast_run >= fast * 0.8
	print("MAULER sprint frames=%d on Running=%d" % [fast, fast_run])
	ok = ok and runs
	print("MAULER_OVERLOAD ", "OK" if ok else "FAIL")
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
