extends Node3D
## Honeypots (HoneypotCache, def key `honeypots`). On a flat baked navmesh
## with a stand-in player:
##   - it wears the real pickup's mesh, is not a pickup, and is not an enemy;
##   - player fire (world + enemy mask) finds it; it never springs for a robot;
##   - it glitches red every GLITCH_MIN..GLITCH_MAX s (the tell);
##   - walking in springs it: SPRING_DAMAGE, `count` `squad` robots around it,
##     the HONEYPOT toast and the hint, and the bait is gone;
##   - hurt first, it is defused: DEFUSE_BONUS, the toast, and a real Pickup of
##     its kind in its place, which nothing springs from.
## Campaign pass: on every level with honeypots, each stands clear of
## geometry, out of every hazard bed, and can be reached from spawn.
##   godot --headless --path . --audio-driver Dummy res://tests/honeypot_probe.tscn

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

func _robots_near(at: Vector3, r: float, type_name: String) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and (e as Node3D).global_position.distance_to(at) <= r \
				and (e as Node).scene_file_path.get_file().get_basename() == type_name:
			n += 1
	return n

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
	pdmg.max_health = 1000.0
	player.add_child(pdmg)
	player.position = Vector3(40, 0.05, 40)
	add_child(player)

	var hp_real := (LevelBuilder.pickup_scene("health").instantiate()) as Node3D
	var real_core := hp_real.get_node("Mesh/Core") as MeshInstance3D
	var bait := HoneypotCache.new()
	bait.kind = "health"
	bait.squad = "skitter"
	bait.count = 3
	add_child(bait)
	await _frames(3)
	var core := bait.find_child("Core", true, false) as MeshInstance3D
	_check(core != null and core.mesh == real_core.mesh, "it wears the real health pack's mesh")
	# Every visual node of the real pickup, or the one it lacks gives it away
	# (the windowed shot found the bait without the real pack's GroundRing).
	var missing: Array[String] = []
	for c in hp_real.get_children():
		if not c is CollisionShape3D and bait.find_child(c.name, true, false) == null:
			missing.append(String(c.name))
	_check(missing.is_empty(), "it carries every visual node of the real pack (missing %s)" % [missing])
	hp_real.free()
	_check(not bait.is_in_group("pickup") and not bait.is_in_group("enemy"), "it is neither a pickup nor an enemy")
	var q := PhysicsRayQueryParameters3D.create(Vector3(0, 0.6, -8), Vector3(0, 0.6, 8), 0b0000101)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	_check(not hit.is_empty() and hit.collider == bait, "player fire (world + enemy mask) finds it")

	# The tell.
	var g0 := bait.glitch_count
	var saw_red := false
	for i in int(HoneypotCache.GLITCH_MAX * 2.2 / 0.05):
		await _seconds(0.05)
		if bait.glitching:
			var l := bait.find_child("Light", true, false) as OmniLight3D
			saw_red = saw_red or (l != null and l.light_color == HoneypotCache.RED)
	_check(bait.glitch_count - g0 >= 2 and saw_red, "it glitches red now and then (%d tears in %.1f s)" % [bait.glitch_count - g0, HoneypotCache.GLITCH_MAX * 2.2])

	# Robots walk past it.
	var walker := CharacterBody3D.new()
	walker.add_to_group("enemy")
	walker.position = Vector3(0.6, 0.05, 0)
	add_child(walker)
	await _frames(10)
	_check(not bait.sprung and is_instance_valid(bait), "a robot beside it does not spring it")
	walker.queue_free()

	# Spring.
	_hints.clear()
	_toasts.clear()
	var hp0 := pdmg.current_health
	player.global_position = Vector3(HoneypotCache.SPRING_RANGE - 0.4, 0.05, 0)
	await _frames(4)
	_check(not is_instance_valid(bait) or bait.sprung, "walking in springs it")
	_check(is_equal_approx(hp0 - pdmg.current_health, HoneypotCache.SPRING_DAMAGE), "it bites for %d (%.1f)" % [int(HoneypotCache.SPRING_DAMAGE), hp0 - pdmg.current_health])
	_check(_toasts.has("HONEYPOT") and _hints.has(HoneypotCache.TEACH_TEXT), "it announces itself and teaches the tell")
	var n := 0
	for i in 20:
		await _seconds(0.25)
		n = _robots_near(Vector3.ZERO, HoneypotCache.RING_RADIUS + 1.5, "skitter")
		if n >= 3:
			break
	_check(n == 3, "its squad of 3 skitters warps in around it (%d)" % n)
	await _frames(2)
	_check(not is_instance_valid(bait), "the bait is gone")
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	await _frames(4)

	# Defuse.
	player.global_position = Vector3(40, 0.05, 40)
	var bait2 := HoneypotCache.new()
	bait2.kind = "ammo"
	bait2.squad = "skitter"
	bait2.count = 3
	bait2.position = Vector3(10, 0, 0)
	add_child(bait2)
	await _frames(3)
	_toasts.clear()
	var s0 := GameState.score
	bait2.hp.apply_damage(4.0, player)
	await _frames(3)
	_check(GameState.score - s0 == HoneypotCache.DEFUSE_BONUS and _toasts.has("HONEYPOT DEFUSED"),
		"a shot defuses it: +%d and the toast (%d, %s)" % [HoneypotCache.DEFUSE_BONUS, GameState.score - s0, _toasts])
	var real: Pickup = null
	for p in get_tree().get_nodes_in_group("pickup"):
		if p is Pickup and (p as Pickup).global_position.distance_to(Vector3(10, 0, 0)) < 0.5:
			real = p
	_check(real != null and real.kind == Pickup.Kind.AMMO, "and the real ammo box drops in its place")
	player.global_position = Vector3(10.5, 0.05, 0)
	await _seconds(1.5)
	_check(_robots_near(Vector3(10, 0, 0), 8.0, "skitter") == 0 and get_tree().get_nodes_in_group("honeypot").is_empty(),
		"walking onto the defused spot springs nothing")
	for p in get_tree().get_nodes_in_group("pickup"):
		p.queue_free()
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	player.queue_free()
	nav.queue_free()
	await _frames(4)

func _in_bed(at: Vector3, beds: Array) -> bool:
	for b in beds:
		var c: Vector3 = b.get("pos", Vector3.ZERO)
		var sz: Vector2 = b.get("size", Vector2.ZERO)
		if absf(at.x - c.x) < sz.x * 0.5 + 0.8 and absf(at.z - c.z) < sz.y * 0.5 + 0.8:
			return true
	return false

func _campaign() -> void:
	var found := 0
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		if def.get("honeypots", []).is_empty():
			continue
		print("level %s:" % id)
		var beds: Array = def.get("lava", []).duplicate()
		for t in def.get("tasks", []):
			beds.append_array((t as Dictionary).get("flood", {}).get("beds", []))
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
		for hn in level.find_children("*", "HoneypotCache", true, false):
			found += 1
			var h := hn as HoneypotCache
			h.set_physics_process(false) # the probe's walk must not spring it
			var at := h.global_position
			var box := BoxShape3D.new()
			box.size = Vector3(1.2, 1.4, 1.2)
			var sq := PhysicsShapeQueryParameters3D.new()
			sq.shape = box
			sq.transform = Transform3D(Basis(), at + Vector3.UP * 0.9)
			sq.collision_mask = 1
			_check(space.intersect_shape(sq, 1).is_empty(), "%s honeypot at %s stands clear of geometry" % [id, at])
			_check(not _in_bed(at, beds), "%s honeypot at %s is out of every hazard bed" % [id, at])
			var near := NavigationServer3D.map_get_closest_point(map, at)
			var path := NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, spawn), near, true)
			_check(path.size() > 1 and path[-1].distance_to(near) < 0.6 and Vector2(near.x - at.x, near.z - at.z).length() < 1.5,
				"%s honeypot at %s can be reached from spawn" % [id, at])
		level.queue_free()
		await _frames(4)
	_check(found >= 2, "campaign levels place honeypots (%d)" % found)
