extends Node3D
## ALIGNED escort (aligned_escort.gd + EnemyBase.escort_goal +
## Damageable.floor_health). Unit pass on a flat baked navmesh with a real
## android and a stand-in player:
##   - the unit spawns hijacked, on the HUD waypoint, with a 1 HP floor;
##   - it waits while the player is far ("waiting for you") and walks toward
##     the ring once the player is within `follow` ("moving");
##   - a hostile robot near it turns its guns on it (traitor priority);
##   - a killing blow leaves it at 1 HP, alive and DOWN: stopped,
##     invulnerable, "REBOOTING"; the player standing by it for 3 s brings it
##     back at 60% health;
##   - walked into the ring, the task completes with the plain label.
## Campaign pass: on every level that authors an escort, the route from `pos`
## to `to` exists on the built navmesh; its length and the unit's walk time
## at chase speed are printed.
##   godot --headless --path . --audio-driver Dummy res://tests/escort_probe.tscn

var _fails: Array[String] = []

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	await _frames(10)
	var prev_state = GameState.current_state
	GameState.current_state = GameState.State.PLAYING
	await _unit()
	GameState.current_state = prev_state
	await _campaign()
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _label(id: String) -> String:
	for t in GameState.level_tasks:
		if t["id"] == id:
			return t["label"]
	return ""

func _floor() -> NavigationRegion3D:
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	fmi.mesh = pm
	nav.add_child(fmi)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(120, 1, 120)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	sb.add_child(cs)
	nav.add_child(sb)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nm.agent_radius = 0.5
	nm.cell_size = 0.25
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh()
	return nav

func _unit() -> void:
	print("unit:")
	var nav := _floor()
	await _frames(10)
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
	var pdmg := Damageable.new()
	pdmg.name = "Damageable"
	pdmg.max_health = 1.0e9
	player.add_child(pdmg)
	player.position = Vector3(50, 0.05, 50)
	add_child(player)

	GameState.reset_tasks()
	GameState.register_task("esc", "Walk it", 0.0)
	var esc := AlignedEscort.new()
	esc.task_id = "esc"
	esc.base_label = "Walk it"
	esc.unit_scene = LevelBuilder.enemy_scene("android")
	esc.goal = Vector3(0, 0, -24)
	esc.goal_radius = 3.5
	esc.follow = 12.0
	esc.position = Vector3(0, 0.2, 10)
	nav.add_child(esc)
	await _frames(20)
	var u := esc.unit
	_check(u != null and is_instance_valid(u), "the ALIGNED unit spawns")
	if u == null:
		return
	_check(u.hijacked and u.is_in_group("objective") and u.hp.floor_health >= 1.0,
		"it is hijacked, on the waypoint, with a 1 HP floor")

	# Far player: it waits.
	var start := u.global_position
	await _frames(60)
	_check(Vector2(u.global_position.x - start.x, u.global_position.z - start.z).length() < 1.0,
		"it waits while the player is far (moved %.2f m)" % start.distance_to(u.global_position))
	_check(_label("esc").ends_with("(waiting for you)"), "label says waiting (%s)" % _label("esc"))

	# Near player: it walks toward the ring. The player keeps up (it walks at
	# chase speed and would leave a standing player behind its follow range).
	var z0 := u.global_position.z
	for i in 8:
		player.global_position = u.global_position + Vector3(2.5, 0, 2.5)
		await _frames(12)
	_check(z0 - u.global_position.z > 2.0, "it walks toward the ring with the player close (%.2f m)" % (z0 - u.global_position.z))
	_check(_label("esc").ends_with("(moving)"), "label says moving (%s)" % _label("esc"))

	# A hostile android nearby turns on it.
	player.global_position = Vector3(50, 0.05, 50)
	var foe: EnemyBase = LevelBuilder.enemy_scene("android").instantiate()
	foe.position = u.global_position + Vector3(-7, 0.2, 0)
	nav.add_child(foe)
	var targeted := false
	for i in 30:
		await _frames(6)
		if is_instance_valid(foe) and foe.target == u:
			targeted = true
			break
	_check(targeted, "a hostile robot turns its guns on the ALIGNED unit")
	# Make the foe the unit's own target, then free it under it (a wreck that
	# despawned): the unit must drop it and keep walking, not freeze.
	if is_instance_valid(foe):
		u.target = foe
		await _frames(2)
		foe.free()
	var p0 := u.global_position
	for i in 6:
		player.global_position = u.global_position + Vector3(2.5, 0, 2.5)
		await _frames(12)
	_check(p0.distance_to(u.global_position) > 1.0,
		"it keeps walking after its target is freed (%.2f m)" % p0.distance_to(u.global_position))

	# Killing blow: down, not dead.
	u.hp.apply_damage(1.0e6, null)
	await _frames(2)
	_check(u.hp.current_health >= 1.0 and u.state != EnemyBase.State.DEAD and is_instance_valid(u),
		"a killing blow leaves it alive at %.1f HP" % u.hp.current_health)
	_check(esc.downed and u.hp.invulnerable and not u.escort_go, "it is DOWN: stopped and invulnerable")
	await _frames(3)
	_check(_label("esc").contains("REBOOTING"), "label says rebooting (%s)" % _label("esc"))
	player.global_position = u.global_position + Vector3(6, 0, 0)
	await _frames(200)
	_check(esc.downed, "it stays down while the player keeps away")
	player.global_position = u.global_position + Vector3(2, 0, 0)
	await _frames(200) # 3.3 s at 60 Hz
	_check(not esc.downed and not u.hp.invulnerable, "standing by it for 3 s reboots it")
	_check(absf(u.hp.current_health - u.hp.max_health * AlignedEscort.REBOOT_HEALTH) < 1.0,
		"it comes back at 60%% health (%.1f of %.1f)" % [u.hp.current_health, u.hp.max_health])

	# Walk it home: keep the player beside it.
	for i in 150:
		if esc.done:
			break
		player.global_position = u.global_position + Vector3(2.5, 0, 2.5)
		await _frames(12)
	_check(GameState.is_task_done("esc"), "walked into the ring, the escort completes")
	_check(_label("esc") == "Walk it", "completed with the plain label (%s)" % _label("esc"))
	_check(u.hijacked and is_instance_valid(u), "it stays aligned afterwards")

	# The bounty director never marks a robot on the player's side: with the
	# ALIGNED unit and three hostiles live, 20 picks never land on the unit
	# (were it a candidate, 20 misses would be a 0.3% chance).
	var hostiles: Array = []
	for k in 3:
		var h: EnemyBase = LevelBuilder.enemy_scene("android").instantiate()
		h.position = Vector3(-45 + k * 3.0, 0.2, 45)
		nav.add_child(h)
		hostiles.append(h)
	await _frames(4)
	var ally_marked := 0
	var hostile_marked := 0
	for i in 20:
		GameState._try_mark_bounty()
		if u.is_bounty:
			ally_marked += 1
		for h in hostiles:
			if h.is_bounty:
				hostile_marked += 1
		u.is_bounty = false
		for h in hostiles:
			h.is_bounty = false
	_check(ally_marked == 0 and hostile_marked == 20,
		"a bounty never lands on the ALIGNED unit (%d of 20; hostiles marked %d)" % [ally_marked, hostile_marked])
	for h in hostiles:
		h.queue_free()
	nav.queue_free()
	player.queue_free()
	GameState.reset_tasks()
	await _frames(4)

func _campaign() -> void:
	var found := 0
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		for t in def.get("tasks", []):
			if t.get("type", "") != "escort":
				continue
			found += 1
			print("level %s:" % id)
			var level := (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate() as Node3D
			add_child(level)
			var map := level.get_world_3d().navigation_map
			var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
			for i in 40:
				await _frames(6)
				if NavigationServer3D.map_get_closest_point(map, spawn) != Vector3.ZERO:
					break
			await _frames(10)
			var from: Vector3 = t.get("pos", Vector3.ZERO)
			var to: Vector3 = t.get("to", Vector3.ZERO)
			var a := NavigationServer3D.map_get_closest_point(map, from)
			var b := NavigationServer3D.map_get_closest_point(map, to)
			var route := NavigationServer3D.map_get_path(map, a, b, true)
			var ends := route.size() > 1 and Vector2(route[-1].x - to.x, route[-1].z - to.z).length() < 2.5
			_check(ends, "%s escort route %s -> %s exists" % [id, from, to])
			var length := 0.0
			for i in range(1, route.size()):
				length += route[i].distance_to(route[i - 1])
			var u: EnemyBase = LevelBuilder.enemy_scene(String(t.get("enemy", "android"))).instantiate()
			var spd: float = u.chase_speed() if u.has_method("chase_speed") else 4.0
			u.free()
			print("  %s escort route %.0f m, %.0f s at %.1f m/s" % [id, length, length / maxf(spd, 0.1), spd])
			level.queue_free()
			await _frames(4)
	_check(found >= 1, "at least one campaign level authors an escort (%d)" % found)
