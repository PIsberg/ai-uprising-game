extends Node3D
## Sentry turrets (SentryTurret, def key `turrets`). Unit pass on a flat floor
## with a stand-in player:
##   - it locks on before it fires: the first round lands no sooner than
##     LOCK_TIME after the player came into view;
##   - a wall between them stops it;
##   - right under the gun (DEAD_ZONE) it cannot hit you, and standing there
##     HACK_SECONDS hacks it; a hacked turret shoots robots and never the
##     player, then burns out after its ally time and fires no more;
##   - an EMP shuts it up for the duration;
##   - shot to pieces it stops for good.
## Campaign pass: on every level with turrets, each stands clear of geometry,
## and the hack spot beside it is on the navmesh and reachable from spawn.
##   godot --headless --path . --audio-driver Dummy res://tests/sentry_turret_probe.tscn

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

func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = at
	add_child(sb)
	return sb

func _player(at: Vector3) -> CharacterBody3D:
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	player.add_child(cs)
	var pdmg := Damageable.new()
	pdmg.name = "Damageable"
	pdmg.max_health = 1.0e9
	player.add_child(pdmg)
	player.position = at
	add_child(player)
	return player

func _hp(p: Node) -> float:
	return (p.get_node("Damageable") as Damageable).current_health

## Seconds until the player first loses health (INF if not within `limit`).
func _time_to_hit(p: Node, limit: float) -> float:
	var h0 := _hp(p)
	var t := 0.0
	while t < limit:
		await _frames(3)
		t += 3.0 / Engine.physics_ticks_per_second
		if _hp(p) < h0:
			return t
	return INF

func _unit() -> void:
	print("unit:")
	var floor_body := _box(Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	var player := _player(Vector3(-40, 0.05, -40)) # out of range
	var tur := SentryTurret.new()
	tur.position = Vector3.ZERO
	add_child(tur)
	await _seconds(0.5)

	player.global_position = Vector3(12, 0.05, 0)
	var first := await _time_to_hit(player, 4.0)
	_check(first < 4.0, "in view and in range, it hits the player (%.2f s)" % first)
	_check(first >= SentryTurret.LOCK_TIME, "never before its lock-on (%.2f s >= %.2f s)" % [first, SentryTurret.LOCK_TIME])

	var wall := _box(Vector3(6, 2, 0), Vector3(1, 4, 6))
	await _seconds(SentryTurret.BURST_GAP + 0.3)
	_check(await _time_to_hit(player, 3.0) == INF, "a wall between them stops it")
	wall.queue_free()

	player.global_position = Vector3(1.4, 0.05, 0.4)
	_check(await _time_to_hit(player, SentryTurret.HACK_SECONDS + 0.4) == INF, "right under the gun it cannot hit you")
	await _seconds(0.3)
	_check(tur.phase == SentryTurret.Phase.ALLIED, "standing there hacks it (phase %d)" % tur.phase)

	var bot: EnemyBase = LevelBuilder.enemy_scene("android").instantiate()
	bot.position = Vector3(-10, 0.2, 6)
	bot.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(bot)
	await _frames(4)
	bot.max_health = 2000.0
	bot.hp.max_health = 2000.0
	bot.hp.current_health = 2000.0
	player.global_position = Vector3(12, 0.05, 0)
	var ph := _hp(player)
	await _seconds(3.0)
	_check(bot.hp.current_health < 2000.0, "hacked, it shoots robots (%.0f HP left)" % bot.hp.current_health)
	_check(_hp(player) >= ph, "and never the player")
	tur.ally_left = 0.05
	await _seconds(0.5)
	_check(tur.phase == SentryTurret.Phase.BURNT, "it burns out when its time is up (phase %d)" % tur.phase)
	var bh := bot.hp.current_health
	ph = _hp(player)
	await _seconds(2.5)
	_check(bot.hp.current_health == bh and _hp(player) >= ph, "burnt out, it fires at nothing")
	bot.queue_free()
	tur.queue_free()
	await _frames(4)

	# EMP, then destruction.
	var t2 := SentryTurret.new()
	add_child(t2)
	await _frames(4)
	player.global_position = Vector3(12, 0.05, 0)
	t2.emp_disable(2.0)
	_check(await _time_to_hit(player, 1.7) == INF, "an EMP shuts it up")
	_check(await _time_to_hit(player, 3.5) < 3.5, "and it wakes after")
	t2.hp.apply_damage(1.0e6, player)
	await _frames(4)
	_check(t2.phase == SentryTurret.Phase.DEAD, "shot to pieces it is dead (phase %d)" % t2.phase)
	await _seconds(SentryTurret.BURST_GAP + 0.2)
	_check(await _time_to_hit(player, 2.5) == INF, "and stays quiet")
	t2.queue_free()
	player.queue_free()
	floor_body.queue_free()
	await _frames(4)

func _campaign() -> void:
	var found := 0
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		if def.get("turrets", []).is_empty():
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
		for tn in level.find_children("*", "SentryTurret", true, false):
			found += 1
			var tur := tn as SentryTurret
			var at := tur.global_position
			var box := BoxShape3D.new()
			box.size = Vector3(1.2, 1.4, 1.2)
			var sq := PhysicsShapeQueryParameters3D.new()
			sq.shape = box
			sq.transform = Transform3D(Basis(), at + Vector3.UP * 0.9)
			sq.collision_mask = 1
			sq.exclude = [tur.get_rid()]
			_check(space.intersect_shape(sq, 1).is_empty(), "%s turret at %s stands clear of geometry" % [id, at])
			var reach := false
			for k in 8:
				var ang := TAU * k / 8.0
				var spot := at + Vector3(cos(ang), 0, sin(ang)) * (SentryTurret.HACK_RANGE - 0.6)
				var near := NavigationServer3D.map_get_closest_point(map, spot)
				if Vector2(near.x - at.x, near.z - at.z).length() > SentryTurret.HACK_RANGE - 0.1:
					continue
				var path := NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, spawn), near, true)
				if path.size() > 1 and path[-1].distance_to(near) < 0.6:
					reach = true
					break
			_check(reach, "%s turret at %s can be reached and hacked from spawn" % [id, at])
		level.queue_free()
		await _frames(4)
	_check(found >= 1, "at least one campaign level places turrets (%d)" % found)
