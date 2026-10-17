extends Node3D
## TELEMETRY LEECH (EnemyLeech, enemy type "leech") against the REAL player
## scene on a flat floor:
##   - it flies in and latches behind the player's head: no collision, in the
##     "leech_latched" group, the hint;
##   - latched it drains about DRAIN_DPS, slows the player to SLOW, and its
##     beacon wakes an unaware robot within BEACON_RANGE but not one beyond;
##   - the melee key rips it off and kills it, and the slow lifts;
##   - the dash key shakes the next one loose, stunned and flung clear, and
##     it comes back for another go;
##   - it cannot latch through dash i-frames; shot in flight, it dies.
##   godot --headless --path . --audio-driver Dummy res://tests/leech_probe.tscn

var _fails: Array[String] = []
var _hints: Array[String] = []
var _player: CharacterBody3D
var _pdmg: Damageable

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _seconds(s: float) -> void:
	await _frames(int(ceil(s * Engine.physics_ticks_per_second)))

func _leech(at: Vector3) -> EnemyLeech:
	var l := (load("res://scenes/enemies/leech.tscn") as PackedScene).instantiate() as EnemyLeech
	l.position = at
	add_child(l)
	return l

func _wait_latch(l: EnemyLeech, s: float) -> void:
	for i in int(s / 0.1):
		if not is_instance_valid(l) or l.latched:
			return
		await _seconds(0.1)

func _press(action: String) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(1)

func _run() -> void:
	GameState.teach_hint.connect(func(t: String) -> void: _hints.append(t))
	var prev_state = GameState.current_state
	GameState.current_state = GameState.State.PLAYING
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(200, 1, 200)
	cs.shape = bs
	cs.position.y = -0.5
	sb.add_child(cs)
	add_child(sb)
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	add_child(_player)
	_player.global_position = Vector3(0, 0.1, 0)
	_pdmg = _player.get_node("Damageable") as Damageable
	_pdmg.max_health = 10000.0
	_pdmg.current_health = 10000.0
	await _seconds(GameState.ATTACK_GRACE if "ATTACK_GRACE" in GameState else 2.5)
	while GameState.attack_grace_active():
		await _seconds(0.2)
	# Two sleeping robots: one inside the beacon's range, one outside it.
	var near := (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate() as EnemyBase
	near.position = Vector3(30, 0.1, 20)
	add_child(near)
	var far := (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate() as EnemyBase
	far.position = Vector3(-60, 0.1, -40)
	add_child(far)
	await _frames(4)
	for r in [near, far]:
		r.set_physics_process(false)
		r.set_process(false)
		r.state = EnemyBase.State.IDLE
	var speed0: float = _player._current_speed()

	print("latch:")
	var l := _leech(Vector3(0, 1.5, -14))
	await _wait_latch(l, 6.0)
	_check(l.latched and l.collision_layer == 0 and l.is_in_group("leech_latched"), "it flies in and latches on, collision off")
	_check(_hints.has(EnemyLeech.TEACH_TEXT), "the latch teaches the answer")
	var cam := _player.get_node("Head/Camera3D") as Node3D
	_check(l.global_position.distance_to(cam.global_position) < 0.6, "it rides behind the player's head (%.2f m)" % l.global_position.distance_to(cam.global_position))
	var hp0 := _pdmg.current_health
	var b0 := l.beacons
	await _seconds(EnemyLeech.BEACON_PERIOD + 0.1)
	var drained := hp0 - _pdmg.current_health
	_check(absf(drained - EnemyLeech.DRAIN_DPS * (EnemyLeech.BEACON_PERIOD + 0.1)) <= 2.0, "it drains about %.0f/s (%.1f in %.1f s)" % [EnemyLeech.DRAIN_DPS, drained, EnemyLeech.BEACON_PERIOD + 0.1])
	_check(is_equal_approx(_player._current_speed(), speed0 * EnemyLeech.SLOW), "it slows the player to x%.1f (%.2f -> %.2f)" % [EnemyLeech.SLOW, speed0, _player._current_speed()])
	_check(l.beacons > b0 and near.state == EnemyBase.State.ALERT and near.target == _player, "its beacon wakes a robot %.0f m away" % near.global_position.distance_to(_player.global_position))
	_check(far.state == EnemyBase.State.IDLE, "but not one %.0f m away" % far.global_position.distance_to(_player.global_position))

	print("melee:")
	await _press("melee")
	await _frames(2)
	_check(not is_instance_valid(l) or l.state == EnemyBase.State.DEAD, "the melee key rips it off and kills it")
	_check(get_tree().get_nodes_in_group("leech_latched").is_empty() and is_equal_approx(_player._current_speed(), speed0), "and the slow lifts")
	await _seconds(1.2) # melee cooldown

	print("dash:")
	var l2 := _leech(Vector3(6, 1.5, -10))
	await _wait_latch(l2, 6.0)
	_check(l2.latched, "a second one latches on")
	await _press("dash")
	_check(not l2.latched and l2._emp_t > 0.0 and l2.collision_layer == 4, "the dash key shakes it loose, stunned, shootable again")
	await _seconds(0.6)
	_check(l2.global_position.distance_to(_player.global_position + Vector3.UP * 1.4) > EnemyLeech.LATCH_RANGE + 1.0, "flung clear (%.1f m)" % l2.global_position.distance_to(_player.global_position + Vector3.UP * 1.4))
	await _wait_latch(l2, 8.0)
	_check(l2.latched, "and it comes back for another go")
	await _press("melee")
	await _seconds(1.2)

	print("i-frames and gunfire:")
	_pdmg.invulnerable = true
	var l3 := _leech(_player.global_position + Vector3(0, 1.4, -0.8))
	await _seconds(1.0)
	_check(not l3.latched, "it cannot latch on through dash i-frames")
	_pdmg.invulnerable = false
	l3.hp.apply_damage(30.0, _player)
	await _frames(3)
	_check(not is_instance_valid(l3) or l3.state == EnemyBase.State.DEAD, "shot in flight, it dies (24 hp)")

	GameState.current_state = prev_state
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)
