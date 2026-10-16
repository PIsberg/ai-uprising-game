extends Node3D
## Spawn nests (SpawnNest, def key `nests`). On a flat baked navmesh with a
## stand-in player:
##   - with the player far away, a nest spawns nothing;
##   - with the player within WAKE_RANGE it spawns its kind every INTERVAL,
##     never more than MAX_ALIVE alive at once;
##   - killing its spawn lets it spawn again (the cap counts the living);
##   - shot to pieces it stops for good, pays BONUS and announces it;
##   - walking up teaches the rule once.
## Campaign pass: on every level with nests, each stands clear of geometry and
## can be reached from spawn.
##   godot --headless --path . --audio-driver Dummy res://tests/spawn_nest_probe.tscn

var _fails: Array[String] = []
var _hints: Array[String] = []
var _toasts: Array[String] = []

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	await _frames(10)
	GameState.teach_hint.connect(func(t: String) -> void: _hints.append(t))
	GameState.skirmish_event.connect(func(t: String, _d: String) -> void: _toasts.append(t))
	var prev_state = GameState.current_state
	GameState.current_state = GameState.State.PLAYING
	await _unit()
	await _campaign()
	GameState.current_state = prev_state
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _seconds(s: float) -> void:
	await _frames(int(ceil(s * Engine.physics_ticks_per_second)))

func _unit() -> void:
	print("unit:")
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
	await _frames(10)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pdmg := Damageable.new()
	pdmg.name = "Damageable"
	pdmg.max_health = 1.0e9
	pdmg.invulnerable = true
	player.add_child(pdmg)
	player.position = Vector3(55, 0.05, 55)
	add_child(player)

	var nest := SpawnNest.new()
	nest.kind = "skitter"
	add_child(nest)
	await _seconds(SpawnNest.INTERVAL * 2.0)
	_check(nest.live.is_empty() and nest.spawned_total == 0, "with the player far away it spawns nothing")

	_hints.clear()
	player.global_position = Vector3(12, 0.05, 0)
	await _seconds(SpawnNest.INTERVAL + 1.5)
	_check(nest.spawned_total >= 1, "with the player near it spawns (%d)" % nest.spawned_total)
	_check(_hints.has(SpawnNest.TEACH_TEXT), "walking up teaches the rule")
	# Freeze the spawn so they stay alive and in place: the cap is about the living.
	for i in int(SpawnNest.MAX_ALIVE + 2):
		for r in nest.live:
			if is_instance_valid(r):
				r.process_mode = Node.PROCESS_MODE_DISABLED
		await _seconds(SpawnNest.INTERVAL)
	_check(nest.live.size() <= SpawnNest.MAX_ALIVE and nest.spawned_total == SpawnNest.MAX_ALIVE,
		"never more than %d alive (%d alive, %d spawned)" % [SpawnNest.MAX_ALIVE, nest.live.size(), nest.spawned_total])
	for r in nest.live.duplicate():
		if is_instance_valid(r):
			r.hp.apply_damage(1.0e6, player)
	await _seconds(SpawnNest.INTERVAL + 1.5)
	_check(nest.spawned_total > SpawnNest.MAX_ALIVE, "killing its spawn lets it spawn again (%d spawned)" % nest.spawned_total)

	_toasts.clear()
	var s0 := GameState.score
	nest.hp.apply_damage(1.0e6, player)
	await _frames(4)
	_check(not is_instance_valid(nest) or nest.dead, "shot to pieces it is dead")
	_check(GameState.score - s0 >= SpawnNest.BONUS and _toasts.has("NEST DESTROYED"), "it pays the bonus and says so (+%d, %s)" % [GameState.score - s0, _toasts])
	var before := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		before += 1
	await _seconds(SpawnNest.INTERVAL * 2.0)
	var after := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		after += 1
	_check(after <= before, "and spawns nothing more (%d -> %d robots)" % [before, after])
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	player.queue_free()
	nav.queue_free()
	await _frames(4)

func _campaign() -> void:
	var found := 0
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		if def.get("nests", []).is_empty():
			continue
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
		var space := level.get_world_3d().direct_space_state
		for nn in level.find_children("*", "SpawnNest", true, false):
			found += 1
			var nest := nn as SpawnNest
			var at := nest.global_position
			var box := BoxShape3D.new()
			box.size = Vector3(1.6, 1.4, 1.6)
			var sq := PhysicsShapeQueryParameters3D.new()
			sq.shape = box
			sq.transform = Transform3D(Basis(), at + Vector3.UP * 0.9)
			sq.collision_mask = 1
			sq.exclude = [nest.get_rid()]
			_check(space.intersect_shape(sq, 1).is_empty(), "%s nest at %s stands clear of geometry" % [id, at])
			var near := NavigationServer3D.map_get_closest_point(map, at)
			var path := NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, spawn), near, true)
			_check(path.size() > 1 and path[-1].distance_to(near) < 0.6 and Vector2(near.x - at.x, near.z - at.z).length() < 3.0,
				"%s nest at %s can be reached from spawn" % [id, at])
		level.queue_free()
		await _frames(4)
	_check(found >= 1, "at least one campaign level places nests (%d)" % found)
