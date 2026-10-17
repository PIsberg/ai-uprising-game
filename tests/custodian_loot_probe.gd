extends Node3D
## CUSTODIAN loot (EnemyVacuum scavenging). A real custodian on a flat floor,
## the stand-in player 30 m off (too far to wake it):
##   - it trundles to a health pack 6 m away in sight and swallows it, bulging,
##     and the swallow teaches the rule;
##   - it leaves a weapon pickup, one behind a wall, and one beyond
##     SCAVENGE_RANGE where they are;
##   - risen to fight, it scavenges nothing;
##   - destroyed, it spills everything it ate, same kinds and amounts.
##   godot --headless --path . --audio-driver Dummy res://tests/custodian_loot_probe.tscn

var _fails: Array[String] = []
var _hints: Array[String] = []

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

func _box(at: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = at
	add_child(sb)

func _pickup(kind: String, at: Vector3, amount: int = -1) -> Pickup:
	var p := LevelBuilder.pickup_scene(kind).instantiate() as Pickup
	if amount >= 0:
		p.amount = amount
	add_child(p)
	p.global_position = at
	return p

func _custodian(at: Vector3) -> EnemyVacuum:
	var v := (load("res://scenes/enemies/vacuum.tscn") as PackedScene).instantiate() as EnemyVacuum
	v.position = at
	add_child(v)
	return v

func _run() -> void:
	GameState.teach_hint.connect(func(t: String) -> void: _hints.append(t))
	var prev_state = GameState.current_state
	GameState.current_state = GameState.State.PLAYING
	_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200))
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pdmg := Damageable.new()
	pdmg.name = "Damageable"
	pdmg.max_health = 100.0
	pdmg.invulnerable = true
	player.add_child(pdmg)
	player.position = Vector3(0, 0.05, 30)
	add_child(player)

	print("scavenge:")
	var v := _custodian(Vector3(0, 0.1, 0))
	v.drop_chance = 0.0 # its own random kill drop would muddle the spill count
	await _frames(10)
	var hp := _pickup("health", Vector3(6, 0, 0), 35)
	var weapon := (load(LevelBuilder.WEAPON_PICKUP_PATH) as PackedScene).instantiate() as Pickup
	add_child(weapon)
	weapon.global_position = Vector3(-4, 0, 0)
	_box(Vector3(0, 1, -5), Vector3(40, 2, 0.4)) # no way round it within range
	var hidden := _pickup("ammo", Vector3(0, 0, -8), 20)
	var far := _pickup("ammo", Vector3(0, 0, EnemyVacuum.SCAVENGE_RANGE + 6.0), 20)
	var sx := v._chassis.scale.x if v._chassis else 1.0
	for i in 60:
		await _seconds(0.1)
		if not is_instance_valid(hp):
			break
	_check(not is_instance_valid(hp) and v.swallowed.size() == 1 and v.swallowed[0]["kind"] == "health" and int(v.swallowed[0]["amount"]) == 35,
		"it trundles to a health pack 6 m away and swallows it (%s)" % [v.swallowed])
	_check(v._chassis and v._chassis.scale.x > sx, "it bulges with what it ate (%.2f -> %.2f)" % [sx, v._chassis.scale.x if v._chassis else 0.0])
	_check(_hints.has(EnemyVacuum.LOOT_TEACH), "the swallow teaches the rule")
	var aimed_hidden := false
	for i in 60:
		await _seconds(0.1)
		aimed_hidden = aimed_hidden or v._loot_target == hidden
	_check(is_instance_valid(weapon), "it never eats a weapon pickup")
	_check(is_instance_valid(hidden) and not aimed_hidden, "nor one behind a wall, nor even heads for it")
	_check(is_instance_valid(far), "nor one beyond %.0f m" % EnemyVacuum.SCAVENGE_RANGE)
	_check(v._phase == EnemyVacuum.Phase.GROUND, "and it stayed a disc throughout")

	print("spill:")
	var at := v.global_position
	var eaten := v.swallowed.duplicate(true)
	v.hp.apply_damage(9999.0, player)
	await _frames(4)
	var out: Array[String] = []
	for n in get_tree().get_nodes_in_group("pickup"):
		var p := n as Pickup
		if p and p != weapon and p != hidden and p != far and p.global_position.distance_to(at) < 2.5:
			out.append("%d:%d" % [int(p.kind), p.amount])
	_check(out.size() == eaten.size() and out.has("0:35"), "destroyed, it spills what it ate (%s from %s)" % [out, eaten])

	print("risen:")
	for n in get_tree().get_nodes_in_group("pickup"):
		n.queue_free()
	var v2 := _custodian(Vector3(20, 0.1, 0))
	await _frames(10)
	v2._begin_rise()
	await _seconds(v2.rise_duration + 0.3)
	v2.set_physics_process(true)
	var bait := _pickup("ammo", v2.global_position + Vector3(3, 0, 0), 20)
	await _seconds(3.0)
	_check(v2._phase == EnemyVacuum.Phase.COMBAT and is_instance_valid(bait) and v2.swallowed.is_empty(), "risen to fight, it scavenges nothing")

	GameState.current_state = prev_state
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)
