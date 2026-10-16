extends Node3D
## DATA LEAK skirmish event (GameState._event_data_leak + InterceptCourier in
## adopt mode). On a flat baked navmesh with a stand-in player:
##   - with only a robot too close to the player and a flyer live, no robot is
##     made a courier (the event falls back to another kind);
##   - with a ground android at mid range, THAT robot becomes the courier: on
##     the waypoint, tagged, running for an uplink at least LEAK_RUN_MIN away
##     from it and farther from the player than it was, so it runs away;
##   - a second leak while one is live makes no second courier;
##   - killing it pays LEAK_BONUS and drops an overclock where it fell;
##   - one that finishes its upload vanishes with no kill credit and an
##     ASSASSIN CONTRACT hunter warps in at the uplink, marked as the bounty.
##   godot --headless --path . --audio-driver Dummy res://tests/data_leak_probe.tscn

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
	var prev_path := GameState.current_level_path
	GameState.current_state = GameState.State.PLAYING
	GameState.current_level_path = "res://scenes/levels/level_gpt.tscn"
	GameState._bounty = null
	await _run()
	GameState.current_state = prev_state
	GameState.current_level_path = prev_path
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _floor() -> NavigationRegion3D:
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	fmi.mesh = pm
	nav.add_child(fmi)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(160, 1, 160)
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

func _robot(nav: Node, kind: String, at: Vector3) -> EnemyBase:
	var e: EnemyBase = LevelBuilder.enemy_scene(kind).instantiate()
	e.position = at
	nav.add_child(e)
	return e

func _couriers() -> Array:
	return get_tree().get_nodes_in_group("intercept_courier")

func _leak_node() -> InterceptCourier:
	for c in find_children("*", "InterceptCourier", true, false):
		if not (c as InterceptCourier).done:
			return c
	return null

func _run() -> void:
	var nav := _floor()
	await _frames(10)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pdmg := Damageable.new()
	pdmg.name = "Damageable"
	pdmg.max_health = 1.0e9
	player.add_child(pdmg)
	player.position = Vector3(0, 0.05, 0)
	add_child(player)

	# No candidate: one robot right on the player, one flyer at mid range.
	var near := _robot(nav, "android", Vector3(4, 0.3, 0))
	var flyer := _robot(nav, "drone", Vector3(0, 3.0, -22))
	await _frames(6)
	_toasts.clear()
	GameState._event_data_leak()
	await _frames(4)
	_check(_couriers().is_empty(), "no courier from a robot on the player or a flyer")
	_check(not _toasts.is_empty() and not _toasts.has("DATA LEAK"),
		"with no candidate the event falls back to another kind (%s)" % [_toasts])
	for n in [near, flyer]:
		n.queue_free()
	_clear_event_leftovers()
	await _frames(4)

	# A mid-range ground robot: it leaks.
	var runner := _robot(nav, "android", Vector3(0, 0.3, 22))
	await _frames(6)
	_toasts.clear()
	var from := runner.global_position
	GameState._event_data_leak()
	await _frames(4)
	var ic := _leak_node()
	_check(ic != null and ic.unit == runner and runner.courier_goal != null,
		"the mid-range android becomes the courier")
	if ic == null:
		return
	_check(runner.is_in_group("objective") and runner.is_in_group("intercept_courier"), "it is on the waypoint")
	_check(_toasts.has("DATA LEAK"), "the event is announced (%s)" % [_toasts])
	_check(_flat(ic.uplink, from) >= GameState.LEAK_RUN_MIN,
		"its uplink is %.1f m from it (>= %.0f)" % [_flat(ic.uplink, from), GameState.LEAK_RUN_MIN])
	_check(_flat(ic.uplink, player.global_position) > _flat(from, player.global_position) + 10.0,
		"the uplink lies away from the player (%.1f m vs %.1f m)" % [_flat(ic.uplink, player.global_position), _flat(from, player.global_position)])
	GameState._event_data_leak()
	await _frames(4)
	_check(_couriers().size() == 1, "a second leak while one is live makes no second courier (%d)" % _couriers().size())
	_clear_event_leftovers(runner)
	await _frames(120)
	_check(_flat(runner.global_position, player.global_position) > _flat(from, player.global_position) + 8.0,
		"it runs away from the player (%.1f m -> %.1f m)" % [_flat(from, player.global_position), _flat(runner.global_position, player.global_position)])
	var s0 := GameState.score
	var died_at := runner.global_position
	runner.hp.apply_damage(1.0e6, player)
	await _frames(6)
	_check(GameState.score - s0 >= GameState.LEAK_BONUS, "the kill pays the leak bonus (+%d)" % (GameState.score - s0))
	var drop := false
	for c in find_children("*", "", true, false):
		if c is Node3D and String(c.scene_file_path).ends_with("overclock.tscn") and _flat((c as Node3D).global_position, died_at) < 3.0:
			drop = true
	_check(drop, "an overclock drops where it fell")
	_clear_event_leftovers()
	await _frames(4)

	# One that gets away.
	var leaker := _robot(nav, "android", Vector3(-22, 0.3, 0))
	await _frames(6)
	GameState._bounty = null
	GameState._event_data_leak()
	await _frames(4)
	var ic2 := _leak_node()
	_check(ic2 != null and ic2.unit == leaker, "a second leak takes the next mid-range robot")
	if ic2 == null:
		return
	var uplink2 := ic2.uplink
	var kills0 := GameState.kills
	var gone := false
	for i in 120: # 30 s
		await _frames(15)
		if not is_instance_valid(leaker) or not leaker.is_inside_tree():
			gone = true
			break
	_check(gone, "a finished upload takes the courier off the map")
	_check(not is_instance_valid(ic2), "and the event's courier node frees itself")
	await _frames(4)
	_check(GameState.kills == kills0, "with no kill credit (%d -> %d)" % [kills0, GameState.kills])
	_check(_toasts.has("DATA LEAKED") and _toasts.has("ASSASSIN CONTRACT"), "the leak is called and a hunter answers (%s)" % [_toasts])
	var hunter: EnemyBase = null
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and (e as EnemyBase).is_bounty:
			hunter = e
	_check(hunter != null and _flat(hunter.global_position, uplink2) < 6.0,
		"the bounty hunter warps in at the uplink (%s)" % [hunter.global_position if hunter else "none"])
	_clear_event_leftovers()
	player.queue_free()
	nav.queue_free()

## Free whatever other event kinds spawned (assassins, flares, phantoms) so
## the next case starts clean.
func _clear_event_leftovers(keep: Node = null) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e != keep and (e as EnemyBase).is_bounty:
			e.queue_free()
	for n in find_children("SupplyFlare*", "", true, false):
		n.queue_free()
	for n in get_tree().root.find_children("SupplyFlare*", "", true, false):
		n.queue_free()
	GameState._bounty = null
	GameState._surge_t = 0.0
