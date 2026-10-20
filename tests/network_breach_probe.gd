extends Node3D
## Probe: NETWORK BREACH (scripts/systems/network_breach.gd), the player's remote hack.
## A real player on a floor, looking down -Z, with a row of networked things ahead:
## (1) the player carries a NetworkBreach with full bandwidth and the "breach" action;
## (2) the target under the crosshair is the one picked (a turret dead ahead beats
##     a barrel 25 deg off), and nothing behind a wall is offered;
## (3) holding the action slows time to SCAN_SCALE; releasing it on the turret turns
##     the turret ALLIED and restores time;
## (4) a breached explosive barrel detonates; a breached laser gate goes dark and a
##     player standing in its live beam takes nothing until it comes back; a
##     breached robot is jammed (EMP'd); each costs its bandwidth;
## (5) a breach the bandwidth cannot pay for is refused and costs nothing; a boss
##     and a lockdown door are never offered; bandwidth refills at REGEN.
##   godot --headless --path . --audio-driver Dummy res://tests/network_breach_probe.tscn

const PLAYER := "res://scenes/player/player.tscn"
const ANDROID := "res://scenes/enemies/android.tscn"
const TITAN := "res://scenes/enemies/titan.tscn"
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _wait_game(seconds: float) -> void:
	var acc := 0.0
	while acc < seconds:
		await get_tree().physics_frame
		acc += get_physics_process_delta_time()

func _box(size: Vector3, pos: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	add_child(sb)
	sb.global_position = pos
	return sb

func _robot(scene: String, pos: Vector3) -> EnemyBase:
	var e: EnemyBase = (load(scene) as PackedScene).instantiate()
	add_child(e)
	e.global_position = pos
	return e

func _run() -> void:
	_box(Vector3(80, 1, 80), Vector3(0, -0.5, 0))
	GameState.set_state(GameState.State.PLAYING)
	var p: CharacterBody3D = (load(PLAYER) as PackedScene).instantiate()
	add_child(p)
	p.global_position = Vector3(0, 0.1, 0)
	p.rotation.y = 0.0
	await _wait_game(0.4)
	var nb := p.get_node_or_null("NetworkBreach")
	_check("the player carries a NetworkBreach", nb != null)
	if nb == null:
		print("RESULT FAIL")
		get_tree().quit(1)
		return
	_check("bandwidth starts full", is_equal_approx(float(nb.bandwidth), NetworkBreach.MAX_BANDWIDTH))
	_check("the breach action is registered", InputMap.has_action(NetworkBreach.ACTION))

	# 2. Targeting.
	var turret := SentryTurret.new()
	add_child(turret)
	turret.global_position = Vector3(0, 0, -14)
	var barrel: Node3D = (load("res://scenes/props/barrel.tscn") as PackedScene).instantiate()
	add_child(barrel)
	barrel.global_position = Vector3(6.5, 0, -14) # ~25 deg right of the crosshair
	var hidden := SentryTurret.new()
	add_child(hidden)
	hidden.global_position = Vector3(-8, 0, -12)
	_box(Vector3(4, 4, 0.5), Vector3(-6.7, 2, -10)) # wall between the player and `hidden`
	await _wait_game(0.3)
	var offered: Array = nb.targets()
	_check("the turret under the crosshair is picked", nb.pick_target() == turret, str(nb.pick_target()))
	_check("a turret behind a wall is not offered", not offered.has(hidden))
	_check("the barrel in view is offered", offered.has(barrel))

	# 3. Scan: hold slows time, release breaches the target.
	Input.action_press(NetworkBreach.ACTION)
	await _wait_game(0.2)
	_check("holding the breach key slows time", Engine.time_scale < 0.6, "time_scale %.2f" % Engine.time_scale)
	var bw0: float = nb.bandwidth
	Input.action_release(NetworkBreach.ACTION)
	await _wait_game(0.1)
	_check("releasing on the turret turns it", turret.phase == SentryTurret.Phase.ALLIED)
	_check("time comes back", is_equal_approx(Engine.time_scale, 1.0), "time_scale %.2f" % Engine.time_scale)
	# (less the regen of the 0.1 s waited since)
	_check("the turret costs its bandwidth", absf(bw0 - float(nb.bandwidth) - turret.breach_cost()) <= NetworkBreach.REGEN * 0.2, "%.1f -> %.1f" % [bw0, nb.bandwidth])

	# 4. The barrel, a laser gate, a robot.
	nb.bandwidth = NetworkBreach.MAX_BANDWIDTH
	_check("a breached barrel detonates", nb.breach(barrel) and (not is_instance_valid(barrel) or barrel.get("_dead") == true))
	var gate := LaserGate.new()
	gate.axis = "x"
	gate.period = 1000.0 # beam 0 (the low one) stays live for the whole check
	add_child(gate)
	gate.global_position = Vector3(20, 0, 0)
	await _wait_game(0.2)
	nb.bandwidth = NetworkBreach.MAX_BANDWIDTH
	_check("a breached laser gate goes dark", nb.breach(gate) and gate.is_breached())
	var stand_in := CharacterBody3D.new()
	stand_in.add_to_group("player")
	var hp2 := Damageable.new()
	hp2.name = "Damageable"
	hp2.max_health = 100.0
	stand_in.add_child(hp2)
	p.remove_from_group("player")
	add_child(stand_in)
	stand_in.global_position = gate.global_position
	await _wait_game(1.0)
	_check("nobody is hurt by a dark gate", is_equal_approx(hp2.current_health, 100.0), "%.0f" % hp2.current_health)
	await _wait_game(LaserGate.BREACH_TIME)
	_check("the gate comes back and bites", hp2.current_health < 100.0, "%.0f" % hp2.current_health)
	stand_in.queue_free()
	p.add_to_group("player")
	var bot := _robot(ANDROID, Vector3(-20, 0, -10))
	await _wait_game(0.3)
	nb.bandwidth = NetworkBreach.MAX_BANDWIDTH
	_check("a breached robot is jammed", nb.breach(bot) and float(bot.get("_emp_t")) > 0.0)

	# 5. Refusals and regen.
	var bot2 := _robot(ANDROID, Vector3(-24, 0, -10))
	await _wait_game(0.3)
	nb.bandwidth = 1.0
	_check("a breach it cannot pay for is refused", not nb.breach(bot2) and float(bot2.get("_emp_t")) <= 0.0 and is_equal_approx(float(nb.bandwidth), 1.0))
	var boss := _robot(TITAN, Vector3(0, 0, -30))
	await _wait_game(0.3)
	_check("a boss is never offered", not nb.can_breach(boss))
	var lock := FirewallBarrier.new()
	lock.quiet = true
	add_child(lock)
	_check("a lockdown door is never offered", not nb.can_breach(lock))
	var b0: float = nb.bandwidth
	await _wait_game(2.0)
	_check("bandwidth refills", float(nb.bandwidth) > b0 + NetworkBreach.REGEN * 0.5, "%.1f -> %.1f" % [b0, nb.bandwidth])

	Engine.time_scale = 1.0
	GameState.set_state(GameState.State.MENU)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
