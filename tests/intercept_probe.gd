extends Node3D
## INTERCEPT task (intercept_courier.gd + EnemyBase.courier_goal). Unit pass on
## a flat baked navmesh with a real android and a stand-in player:
##   - the courier spawns on the HUD waypoint, tagged, with its health raised;
##   - it runs the authored route leg by leg, slower than the player sprints and
##     faster than the player walks, and never turns to fight the player;
##   - an EMP stops it cold for the duration;
##   - at the uplink it stops and UPLOADS; a finished upload is a copy that
##     escaped: the courier comes back at the route start at full health, the
##     `escaped` signal fires (the level spawns its penalty squad on it) and the
##     task stays open;
##   - killing it completes the task; only a kill with no copy escaped pays the
##     CLEAN INTERCEPT bonus;
##   - hijacking it completes the task too (it is yours, codes and all).
## Campaign pass: on every level that authors an intercept, every leg of the
## route exists on the built navmesh, and the run is long enough to be a chase.
##   godot --headless --path . --audio-driver Dummy res://tests/intercept_probe.tscn

## A route shorter than this many seconds at courier speed is a sprint to a
## kill, not a chase (the player starts the task some way off the courier).
const MIN_RUN_SECONDS := 12.0

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
	await _clean_and_turned()
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

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

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

func _player(at: Vector3) -> CharacterBody3D:
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
	player.position = at
	add_child(player)
	return player

func _courier(nav: Node, id: String, upload: float) -> InterceptCourier:
	GameState.register_task(id, "Run it down", 0.0)
	var ic := InterceptCourier.new()
	ic.task_id = id
	ic.base_label = "Run it down"
	ic.unit_scene = LevelBuilder.enemy_scene("android")
	ic.route = [Vector3(-20, 0, 10), Vector3(-20, 0, -20)]
	ic.uplink = Vector3(10, 0, -20)
	ic.upload_seconds = upload
	ic.position = Vector3(10, 0.2, 10)
	nav.add_child(ic)
	return ic

func _unit() -> void:
	print("unit:")
	var nav := _floor()
	await _frames(10)
	var player := _player(Vector3(45, 0.05, 45))
	GameState.reset_tasks()
	var ic := _courier(nav, "run", 1.5)
	var escapes: Array[int] = []
	ic.escaped.connect(func(n: int) -> void: escapes.append(n))
	await _frames(20)
	var u := ic.unit
	_check(u != null and is_instance_valid(u), "the courier spawns")
	if u == null:
		return
	_check(u.is_in_group("objective") and u.is_in_group("enemy"), "it is on the HUD waypoint and still a hostile")
	_check(u.hp.max_health >= u.max_health * 2.0,
		"its health is raised (%.0f over a stock %.0f)" % [u.hp.max_health, u.max_health])
	_check(_label("run").contains("fleeing"), "label says fleeing (%s)" % _label("run"))

	# Leg 1 runs west along z=10. Time it over 1.5 s once it is up to speed.
	await _frames(30)
	var p0 := u.global_position
	await _frames(90)
	var spd := _flat(p0, u.global_position) / 1.5
	var walk := 5.5
	var sprint := 9.0
	_check(spd > walk and spd < sprint,
		"it runs faster than the player walks and slower than the player sprints (%.2f m/s)" % spd)

	# The player right beside it: it keeps running and never fires on the player.
	var hp0: float = player.get_node("Damageable").current_health
	var x0 := u.global_position.x
	for i in 10:
		player.global_position = u.global_position + Vector3(0, 0, 3.0)
		await _frames(12)
	_check(u.state != EnemyBase.State.ATTACK and x0 - u.global_position.x > 4.0,
		"with the player beside it, it keeps running the route (%.1f m)" % (x0 - u.global_position.x))
	_check(player.get_node("Damageable").current_health >= hp0, "it never damages the player")
	player.global_position = Vector3(45, 0.05, 45)

	# EMP: stopped cold.
	u.emp_disable(2.0)
	await _frames(20)
	var pe := u.global_position
	await _frames(60)
	_check(_flat(pe, u.global_position) < 0.4, "an EMP stops it (%.2f m in 1 s)" % _flat(pe, u.global_position))
	await _frames(80)

	# Run to the uplink: it turns the corner at leg 1's end and arrives.
	var arrived := false
	for i in 120:
		await _frames(6)
		if ic.uploading:
			arrived = true
			break
	_check(arrived, "it reaches the uplink after the corner (leg %d)" % ic.leg)
	_check(_flat(u.global_position, ic.uplink) < 3.0, "it uploads at the uplink (%.1f m off)" % _flat(u.global_position, ic.uplink))
	await _frames(4)
	_check(_label("run").contains("UPLOADING"), "label says uploading (%s)" % _label("run"))
	var pu := u.global_position
	await _frames(40)
	_check(_flat(pu, u.global_position) < 0.6, "it holds still while it uploads")

	# Let the 1.5 s upload finish: a copy escapes, the courier restarts.
	u.hp.apply_damage(40.0, player)
	for i in 30:
		await _frames(6)
		if not escapes.is_empty():
			break
	_check(escapes == [1], "a finished upload fires escaped(1) (%s)" % [escapes])
	await _frames(4)
	_check(ic.copies == 1 and not ic.uploading and not GameState.is_task_done("run"),
		"the task stays open after a copy escapes")
	_check(_flat(u.global_position, ic.position) < 2.5,
		"the backup courier restarts at the route start (%.1f m off)" % _flat(u.global_position, ic.position))
	_check(u.hp.current_health >= u.hp.max_health - 0.5, "and at full health (%.0f of %.0f)" % [u.hp.current_health, u.hp.max_health])
	_check(_label("run").contains("1 copy escaped"), "label counts the copy (%s)" % _label("run"))

	# Kill it: done, but no clean bonus.
	var s0 := GameState.score
	u.hp.apply_damage(1.0e6, player)
	await _frames(6)
	_check(GameState.is_task_done("run"), "killing it completes the task")
	_check(_label("run") == "Run it down", "completed with the plain label (%s)" % _label("run"))
	_check(GameState.score - s0 < InterceptCourier.CLEAN_BONUS,
		"no CLEAN INTERCEPT bonus once a copy escaped (+%d)" % (GameState.score - s0))
	nav.queue_free()
	player.queue_free()
	GameState.reset_tasks()
	await _frames(4)

func _clean_and_turned() -> void:
	print("clean kill + hijack:")
	var nav := _floor()
	await _frames(10)
	var player := _player(Vector3(45, 0.05, 45))
	GameState.reset_tasks()
	var a := _courier(nav, "clean", 10.0)
	await _frames(30)
	var s0 := GameState.score
	a.unit.hp.apply_damage(1.0e6, player)
	await _frames(6)
	_check(GameState.is_task_done("clean"), "a clean kill completes the task")
	_check(GameState.score - s0 >= InterceptCourier.CLEAN_BONUS,
		"and pays the CLEAN INTERCEPT bonus (+%d)" % (GameState.score - s0))

	var b := _courier(nav, "turned", 10.0)
	await _frames(30)
	_check(b.unit.hijack(30.0, player), "the courier can be hijacked")
	await _frames(6)
	_check(GameState.is_task_done("turned"), "a hijacked courier completes the task")
	var pb := b.unit.global_position
	await _frames(60)
	_check(_flat(pb, b.unit.global_position) < 3.0 or b.unit.target != null,
		"a turned courier stops running for the uplink")
	nav.queue_free()
	player.queue_free()
	GameState.reset_tasks()
	await _frames(4)

func _campaign() -> void:
	var found := 0
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		for t in def.get("tasks", []):
			if t.get("type", "") != "intercept":
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
			var pts: Array = [t.get("pos", Vector3.ZERO)]
			pts.append_array(t.get("route", []))
			pts.append(t.get("to", Vector3.ZERO))
			var length := 0.0
			for k in range(1, pts.size()):
				var a := NavigationServer3D.map_get_closest_point(map, pts[k - 1])
				var b := NavigationServer3D.map_get_closest_point(map, pts[k])
				var leg := NavigationServer3D.map_get_path(map, a, b, true)
				var ends := leg.size() > 1 and _flat(leg[-1], pts[k]) < 2.5
				_check(ends, "%s leg %d %s -> %s exists" % [id, k, pts[k - 1], pts[k]])
				for i in range(1, leg.size()):
					length += leg[i].distance_to(leg[i - 1])
			var spd: float = t.get("speed", InterceptCourier.DEFAULT_SPEED)
			var secs := length / spd
			print("  %s courier route %.0f m, %.1f s at %.1f m/s, upload %.0f s" % [id, length, secs, spd, t.get("upload", InterceptCourier.DEFAULT_UPLOAD)])
			_check(secs >= MIN_RUN_SECONDS, "%s route is a chase (%.1f s >= %.0f s)" % [id, secs, MIN_RUN_SECONDS])
			# Run a courier through the real geometry (stairs, gateposts, the
			# traps it must pass): a nav path can exist that a body still snags on.
			GameState.register_task("probe_run", "probe run", 0.0)
			var ic := InterceptCourier.new()
			ic.task_id = "probe_run"
			ic.unit_scene = LevelBuilder.enemy_scene(String(t.get("enemy", "android")))
			ic.route = t.get("route", [])
			ic.uplink = t.get("to", Vector3.ZERO)
			ic.speed = spd
			ic.upload_seconds = 1000.0
			ic.position = t.get("pos", Vector3.ZERO) + Vector3.UP * 0.3
			level.add_child(ic)
			var budget := secs * 2.0 + 6.0
			var ran := 0.0
			while ran < budget and not ic.uploading:
				await _frames(15)
				ran += 0.25
			var where: Vector3 = ic.unit.global_position if is_instance_valid(ic.unit) else Vector3.ZERO
			_check(ic.uploading, "%s courier runs the real route to the uplink (%.1f s of %.0f; leg %d at %s)" % [id, ran, budget, ic.leg, where])
			level.queue_free()
			await _frames(4)
	_check(found >= 1, "at least one campaign level authors an intercept (%d)" % found)
