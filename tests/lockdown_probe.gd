extends Node3D
## Smart-home LOCKDOWN (LockdownZone + FirewallBarrier.starts_open/raise +
## EnemySpawner.spawned). Unit pass on a flat baked navmesh with a stand-in
## player:
##   - armed and open while the player is outside;
##   - stepping inside raises the door and announces it;
##   - wave 1 warps in inside the room; killing it brings wave 2; the door
##     holds until the last wave robot is down, then drops, pays BONUS and
##     pops the safe's supplies; a cleared zone never re-seals;
##   - a death mid-lockdown drops the door and re-arms the zone;
##   - MAX_LOCK seconds sealed releases it whatever is left (no soft-lock).
## Campaign pass: on every level whose open building authors a lockdown, the
## door sheet stands in the doorway and spans it, the level's player stepping
## inside seals it, and every wave-1 robot lands inside the house.
##   godot --headless --path . --audio-driver Dummy res://tests/lockdown_probe.tscn

var _fails: Array[String] = []
var _toasts: Array[String] = []

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	await _frames(10)
	GameState.skirmish_event.connect(func(t: String, _d: String) -> void: _toasts.append(t))
	var prev_state = GameState.current_state
	GameState.current_state = GameState.State.PLAYING
	await _unit()
	await _death_and_timeout()
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

func _floor() -> NavigationRegion3D:
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	fmi.mesh = pm
	nav.add_child(fmi)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80, 1, 80)
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

func _player(at: Vector3) -> CharacterBody3D:
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pdmg := Damageable.new()
	pdmg.name = "Damageable"
	pdmg.max_health = 1.0e9
	player.add_child(pdmg)
	player.position = at
	add_child(player)
	return player

func _zone(nav: Node, at: Vector3) -> LockdownZone:
	var door := FirewallBarrier.new()
	door.length = 2.8
	door.starts_open = true
	door.position = at + Vector3(0, 0, 4.2)
	nav.add_child(door)
	var z := LockdownZone.new()
	z.half = Vector3(3.6, 3.0, 3.6)
	z.doors = [door]
	z.waves = [
		[{"type": "dog", "count": 2, "pos": Vector3(1.5, 0, 1.5)}],
		[{"type": "android", "count": 1, "pos": Vector3(-1.5, 0, -1.5)}],
	]
	z.position = at
	nav.add_child(z)
	return z

func _kill_wave(z: LockdownZone) -> void:
	for r in z.live.duplicate():
		if is_instance_valid(r) and r.hp:
			r.hp.apply_damage(1.0e6, null)

## Wait until wave `w` (0-based) has `n` robots in.
func _wait_wave(z: LockdownZone, w: int, n: int, budget: float) -> bool:
	var t := 0.0
	while t < budget:
		await _frames(15)
		t += 0.25
		if z.wave == w and z.spawned_this_wave >= n:
			await _frames(4)
			return true
	return false

func _pickups_near(at: Vector3, r: float) -> int:
	var n := 0
	for c in get_tree().current_scene.find_children("*", "", true, false):
		if c is Node3D and String(c.scene_file_path).begins_with("res://scenes/pickups/") \
				and (c as Node3D).global_position.distance_to(at) < r:
			n += 1
	return n

func _unit() -> void:
	print("unit:")
	var nav := _floor()
	await _frames(10)
	var player := _player(Vector3(20, 0.05, 0))
	var z := _zone(nav, Vector3.ZERO)
	await _seconds(1.0)
	_check(z.phase == LockdownZone.Phase.ARMED and z.doors[0].is_open, "armed and open while the player is outside")

	_toasts.clear()
	player.global_position = Vector3(0, 0.05, 0)
	await _seconds(LockdownZone.SEAL_WARN + 0.4)
	_check(not z.doors[0].is_open, "stepping inside raises the door")
	_check(_toasts.has("LOCKDOWN"), "and announces it (%s)" % [_toasts])

	_check(await _wait_wave(z, 0, 2, 4.0), "wave 1 warps in (%d robots)" % z.spawned_this_wave)
	var inside := true
	for r in z.live:
		var l: Vector3 = r.global_position - z.global_position
		if absf(l.x) > z.half.x + 0.5 or absf(l.z) > z.half.z + 0.5:
			inside = false
	_check(inside, "inside the room")
	await _seconds(LockdownZone.WAVE_GAP + 1.5)
	_check(z.wave == 0 and not z.doors[0].is_open, "no kill, no progress: still wave 1, still sealed (wave %d)" % z.wave)
	_kill_wave(z)
	_check(await _wait_wave(z, 1, 1, 6.0), "killing it brings wave 2 (wave %d)" % z.wave)
	_check(not z.doors[0].is_open, "the door holds through the waves")
	var s0 := GameState.score
	_kill_wave(z)
	await _seconds(LockdownZone.WAVE_GAP + 0.6)
	_check(z.doors[0].is_open and z.phase == LockdownZone.Phase.CLEARED, "the last kill drops the door (phase %d)" % z.phase)
	_check(GameState.score - s0 >= LockdownZone.BONUS, "and pays the bonus (+%d)" % (GameState.score - s0))
	_check(_pickups_near(z.global_position, 4.0) >= 2, "and pops the safe (%d pickups)" % _pickups_near(z.global_position, 4.0))
	await _seconds(2.0)
	_check(z.doors[0].is_open, "a cleared zone never re-seals")
	player.queue_free()
	nav.queue_free()
	await _frames(4)

func _death_and_timeout() -> void:
	print("death + timeout:")
	var nav := _floor()
	await _frames(10)
	var player := _player(Vector3(20, 0.05, 0))
	var z := _zone(nav, Vector3.ZERO)
	await _frames(4)
	player.global_position = Vector3(0, 0.05, 0)
	await _seconds(LockdownZone.SEAL_WARN + 0.4)
	_check(not z.doors[0].is_open, "sealed")
	player.global_position = Vector3(20, 0.05, 0) # respawned elsewhere
	GameState.player_died.emit()
	await _frames(6)
	_check(z.doors[0].is_open, "a death drops the door")
	await _seconds(LockdownZone.REARM + 0.4)
	_check(z.phase == LockdownZone.Phase.ARMED, "and re-arms the zone (phase %d)" % z.phase)

	z.max_lock = 3.0
	var released: Array = []
	z.released.connect(func(cleared: bool) -> void: released.append(cleared))
	player.global_position = Vector3(0, 0.05, 0)
	await _seconds(LockdownZone.SEAL_WARN + 0.4)
	_check(not z.doors[0].is_open, "sealed again")
	await _seconds(3.5)
	_check(z.doors[0].is_open and released == [false], "MAX_LOCK releases it uncleared (%s)" % [released])
	player.queue_free()
	nav.queue_free()
	await _frames(4)

func _campaign() -> void:
	var found := 0
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		var has := false
		for b in def.get("buildings", []):
			if b.get("open", false) and b.has("lockdown"):
				has = true
		if not has:
			continue
		print("level %s:" % id)
		var level := (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate() as Node3D
		add_child(level)
		await _frames(40)
		for zn in level.find_children("*", "LockdownZone", true, false):
			found += 1
			var z := zn as LockdownZone
			var door: FirewallBarrier = z.doors[0]
			var dl := door.global_position - z.global_position
			_check(door.starts_open and door.is_open, "%s door starts open" % id)
			_check(door.length >= 2.6, "%s door sheet spans the 2.6 m doorway (%.1f m)" % [id, door.length])
			var axis_off := minf(absf(dl.x), absf(dl.z))
			var out := maxf(absf(dl.x), absf(dl.z))
			var wall := z.half.z if absf(dl.z) >= absf(dl.x) else z.half.x
			_check(axis_off < 0.3 and absf(out - wall) < 0.8,
				"%s door is centred on the front wall (offset %s, wall at %.1f)" % [id, dl, wall])
			var from := z.global_position + Vector3.UP * 1.2
			var to := door.global_position + Vector3.UP * 1.2
			var q := PhysicsRayQueryParameters3D.create(from, to, 1)
			var hit := level.get_world_3d().direct_space_state.intersect_ray(q)
			_check(hit.is_empty() or (hit.position as Vector3).distance_to(to) < 0.6,
				"%s door stands in the doorway, not against a wall (%s)" % [id, hit.get("position", "clear")])
			for e in get_tree().get_nodes_in_group("enemy"):
				(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
			var player := get_tree().get_first_node_in_group("player") as Node3D
			player.get_node("Damageable").set("invulnerable", true)
			player.global_position = z.global_position + Vector3.UP * 0.2
			await _seconds(LockdownZone.SEAL_WARN + 0.5)
			_check(not door.is_open, "%s stepping inside seals the house" % id)
			var n := 0
			for spec in z.waves[0]:
				n += int(spec.get("count", 1))
			_check(await _wait_wave(z, 0, n, 5.0), "%s wave 1 warps in (%d of %d)" % [id, z.spawned_this_wave, n])
			for r in z.live:
				var l: Vector3 = r.global_position - z.global_position
				_check(absf(l.x) <= z.half.x + 0.3 and absf(l.z) <= z.half.z + 0.3 and l.y > -0.5 and l.y < z.half.y * 2.0,
					"%s wave robot lands inside the house (%s)" % [id, l])
			z.release(false)
		level.queue_free()
		await _frames(4)
	_check(found >= 1, "at least one campaign house authors a lockdown (%d)" % found)
