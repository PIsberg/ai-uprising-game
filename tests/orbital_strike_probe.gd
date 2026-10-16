extends Node3D
## ORBITAL STRIKE skirmish event (OrbitalStrike, GameState._event_orbital_strike).
## On a flat floor with a stand-in player:
##   - the reticle tracks the player while TRACKING (within 2 m after they move);
##   - standing still through the lock is a hit (STRIKE_DAMAGE);
##   - stepping out of the locked circle during LOCK is a miss;
##   - standing under a roof is a miss (the beam comes from the sky);
##   - a robot standing on the locked spot is untouched (traps spare robots);
##   - the event announces itself and frees its node when done.
##   godot --headless --path . --audio-driver Dummy res://tests/orbital_strike_probe.tscn

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

func _hp(p: Node) -> float:
	return (p.get_node("Damageable") as Damageable).current_health

func _strike() -> OrbitalStrike:
	for c in find_children("*", "OrbitalStrike", true, false):
		return c
	for c in get_tree().root.find_children("*", "OrbitalStrike", true, false):
		return c
	return null

func _run() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(120, 1, 120))
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pdmg := Damageable.new()
	pdmg.name = "Damageable"
	pdmg.max_health = 1000.0
	player.add_child(pdmg)
	player.position = Vector3(0, 0.05, 0)
	add_child(player)
	await _frames(4)

	# 1. Still through the lock: a hit. The event fires it through GameState.
	_toasts.clear()
	GameState._event_orbital_strike()
	await _frames(2)
	var s := _strike()
	_check(s != null and _toasts.has("ORBITAL STRIKE"), "the event spawns a strike and announces it (%s)" % [_toasts])
	if s == null:
		return
	player.global_position = Vector3(6, 0.05, 0)
	await _seconds(2.0)
	_check(s.reticle_pos().distance_to(player.global_position) < 2.0, "the reticle tracks the player (%.1f m off)" % s.reticle_pos().distance_to(player.global_position))
	var h0 := _hp(player)
	await _seconds(OrbitalStrike.TRACK_TIME + OrbitalStrike.LOCK_TIME)
	_check(h0 - _hp(player) >= OrbitalStrike.DAMAGE - 0.1, "standing still through the lock is a hit (-%.0f)" % (h0 - _hp(player)))
	await _seconds(1.0)
	_check(not is_instance_valid(s), "the strike frees itself when done")

	# 2. Step out of the circle during the lock: a miss.
	s = OrbitalStrike.new()
	add_child(s)
	await _seconds(OrbitalStrike.TRACK_TIME + 0.2)
	_check(s.phase == OrbitalStrike.Phase.LOCK, "it locks after tracking (phase %d)" % s.phase)
	player.global_position += Vector3(OrbitalStrike.RADIUS + 2.0, 0, 0)
	h0 = _hp(player)
	await _seconds(OrbitalStrike.LOCK_TIME + 0.4)
	_check(_hp(player) >= h0, "stepping out of the locked circle is a miss")

	# 3. Under a roof: a miss.
	var roof := _box(player.global_position + Vector3(0, 3.5, 0), Vector3(6, 0.4, 6))
	await _frames(2)
	s = OrbitalStrike.new()
	add_child(s)
	h0 = _hp(player)
	await _seconds(OrbitalStrike.TRACK_TIME + OrbitalStrike.LOCK_TIME + 0.4)
	_check(_hp(player) >= h0, "under a roof the beam never reaches you")
	roof.queue_free()

	# 4. A robot on the locked spot is untouched.
	var bot: EnemyBase = LevelBuilder.enemy_scene("android").instantiate()
	bot.process_mode = Node.PROCESS_MODE_DISABLED
	bot.position = player.global_position + Vector3(0.5, 0.2, 0)
	add_child(bot)
	await _frames(4)
	var bh := bot.hp.current_health
	s = OrbitalStrike.new()
	add_child(s)
	await _seconds(OrbitalStrike.TRACK_TIME + 0.2)
	player.global_position += Vector3(OrbitalStrike.RADIUS + 2.0, 0, 0)
	await _seconds(OrbitalStrike.LOCK_TIME + 0.4)
	_check(bot.hp.current_health >= bh, "a robot on the locked spot is untouched")
	bot.queue_free()

	# 5. Fired at a player already under a roof (an indoor level): no strike,
	# the event falls back to another kind.
	var lid := _box(player.global_position + Vector3(0, 3.5, 0), Vector3(6, 0.4, 6))
	await _frames(2)
	_toasts.clear()
	GameState._event_orbital_strike()
	await _frames(2)
	_check(get_tree().get_nodes_in_group("orbital_strike").is_empty() and not _toasts.has("ORBITAL STRIKE") and not _toasts.is_empty(),
		"under a roof the event falls back instead (%s)" % [_toasts])
	for n in get_tree().root.find_children("SupplyFlare*", "", true, false):
		n.queue_free()
	lid.queue_free()
	player.queue_free()
