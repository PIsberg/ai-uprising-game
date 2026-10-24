extends Node3D
## MELTDOWN: a robot thrown into a LavaHazard bed melts (water: short-circuits
## and drowns) and the bed's kill pays GameState.MELTDOWN_BONUS, counts on the
## debrief and flashes the HUD. Explosions do the throwing (BlastPush). Beds are
## 8 x 4 m; the robot slab is inset LavaHazard.ROBOT_INSET from each edge. The
## held robots below are marked thrown with a zero-velocity launch.
##   - a thrown android 2.5 m outside a lava bed takes nothing in 2 s;
##   - a thrown android brushing 0.25 m inside the bed's edge takes nothing (the inset);
##   - a thrown android in the bed dies within 2.5 s, the kill is an environmental kill
##     of the lava kind, pays at least MELTDOWN_BONUS + its own 150 and teaches
##     the rule once;
##   - a drone (flyer) in the bed takes nothing;
##   - a boss-sized android in the bed takes the plain tick (at most 3 ticks in
##     1.1 s), not the melt multiple;
##   - an android in a WATER bed is EMP-stunned by its first tick and drowns:
##     an environmental kill of the water kind;
##   - a bed with melts_robots off (a ladle pour, a flood) burns no robot;
##   - a player grenade 1.5 m from a live android throws it (is_launched right
##     after, at least 2 m further off within 1.2 s); a boss-sized android is
##     not thrown; a grenade a robot threw throws nobody;
##   - the headline: a grenade behind an android standing 0.6 m from a lava bed
##     lands it in the bed, where it melts (the second lava kill);
##   - a robot that merely stands in the bed (spawned there, never thrown) is not
##     burned, and the thrown state ends THROWN_GRACE after a throw.
##   godot --headless --path . --audio-driver Dummy res://tests/meltdown_probe.tscn

const ANDROID := preload("res://scenes/enemies/android.tscn")
const DRONE := preload("res://scenes/enemies/drone.tscn")
const GRENADE := preload("res://scenes/weapons/grenade.tscn")

var _fail: Array[String] = []
var _kills: Array[String] = [] ## kind of every environmental kill, in order
var _hints: Array[String] = []
var _shooter: Node3D

func _check(cond: bool, label: String, detail: String = "") -> void:
	print(("  ok   " if cond else "  FAIL ") + label + ("  (" + detail + ")" if detail != "" else ""))
	if not cond:
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

func _wait(secs: float) -> void:
	var t := 0.0
	while t < secs:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _bed(pos: Vector3, water: bool = false, melts: bool = true) -> LavaHazard:
	var b := LavaHazard.new()
	b.size = Vector2(8.0, 4.0)
	b.water = water
	b.melts_robots = melts
	add_child(b)
	b.global_position = pos
	return b

func _robot(pos: Vector3, scene: PackedScene = ANDROID) -> EnemyBase:
	var e: EnemyBase = scene.instantiate()
	add_child(e)
	e.global_position = pos
	return e

func _grenade(pos: Vector3, shooter: Node) -> void:
	var g: Grenade = GRENADE.instantiate()
	add_child(g)
	g.global_position = pos
	g.throw_grenade(Vector3.ZERO, shooter)
	g._explode()

func _taken(e: EnemyBase) -> float:
	return e.hp.max_health - e.hp.current_health if is_instance_valid(e) else INF

func _dead(e: EnemyBase) -> bool:
	return not is_instance_valid(e) or not e.hp.is_alive()

func _run() -> void:
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(400, 1, 400)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	_shooter = Node3D.new()
	_shooter.add_to_group("player")
	add_child(_shooter)
	_shooter.global_position = Vector3(0, 1.5, -40)
	GameState.set_state(GameState.State.PLAYING)
	GameState._taught.erase("meltdown")
	GameState.stat_meltdowns = 0
	GameState.environmental_kill.connect(func(k: String, p: Vector3) -> void:
		_kills.append(k)
		print("  kill  %s at %v" % [k, p]))
	GameState.teach_hint.connect(func(t: String) -> void: _hints.append(t))

	var lava := _bed(Vector3.ZERO)
	_bed(Vector3(0, 0, 30), true)
	_bed(Vector3(0, 0, 60), false, false)
	_check(lava.melts_robots and lava._robot_zone != null, "a lava bed builds its robot slab")

	var control := _robot(Vector3(6.5, 0.1, 0))
	var graze := _robot(Vector3(3.75, 0.1, 0))
	var melt := _robot(Vector3(0, 0.1, 0))
	var flyer := _robot(Vector3(2, 0.3, 0), DRONE)
	var boss := _robot(Vector3(-2, 0.1, 0))
	var drown := _robot(Vector3(0, 0.1, 30))
	var safe := _robot(Vector3(0, 0.1, 60))
	await _wait(0.2)
	boss.hp.max_health = 900.0
	boss.hp.current_health = 900.0
	boss.max_health = 900.0
	boss.score_value = 1000
	var bystander := _robot(Vector3(2.5, 0.1, 1.2)) # in the bed, clear of the headline grenade
	await _wait(0.2)
	for e: EnemyBase in [control, graze, melt, flyer, boss, drown, safe, bystander]:
		e.set_physics_process(false) # hold them where they stand
	for e: EnemyBase in [control, graze, melt, flyer, boss, drown, safe]:
		e.launch(Vector3.ZERO, 0.1) # thrown in place (physics is off: the state holds)
	var score0 := GameState.score
	await _wait(1.1)
	var boss_taken := _taken(boss)
	_check(boss_taken > 0.0 and boss_taken <= lava.damage_per_tick * 3.0 + 0.5,
			"a boss-sized robot takes the plain tick, not the melt multiple",
			"%.0f in 1.1 s, a tick is %.0f" % [boss_taken, lava.damage_per_tick])
	boss.queue_free() # held (physics off) it would stay thrown and burn to death later
	_check(is_instance_valid(drown) and drown._emp_t > 0.0, "a robot in water is short-circuited (EMP)")
	await _wait(1.4)
	_check(_taken(control) == 0.0, "a robot 2.5 m outside the bed is untouched", "%.0f" % _taken(control))
	_check(_taken(graze) == 0.0, "a robot brushing 0.25 m inside the edge is untouched (inset)", "%.0f" % _taken(graze))
	_check(_taken(flyer) == 0.0, "a drone over the bed is untouched", "%.0f" % _taken(flyer))
	_check(_taken(safe) == 0.0, "a bed with melts_robots off burns no robot", "%.0f" % _taken(safe))
	_check(_taken(bystander) == 0.0, "a robot that merely stands in the bed (never thrown) is not burned", "%.0f" % _taken(bystander))
	_check(_dead(melt), "a robot in the bed melts within 2.5 s")
	_check(_dead(drown), "a robot in water drowns within 2.5 s")
	_check(_kills.size() == 2 and _kills.has("lava") and _kills.has("water"),
			"one lava kill and one water kill are reported", str(_kills))
	_check(GameState.stat_meltdowns == 2, "the debrief count is 2", str(GameState.stat_meltdowns))
	_check(GameState.score - score0 >= 2 * (GameState.MELTDOWN_BONUS + 150),
			"both kills pay the bonus on top of the kill", "+%d" % (GameState.score - score0))
	_check(_hints.count(GameState.MECHANIC_HINTS["meltdown"]) == 1, "the first meltdown teaches the rule once", str(_hints.size()))

	# The thrown state ends after THROWN_GRACE.
	var grace := _robot(Vector3(80, 0.1, 0))
	await _wait(0.2)
	grace.launch(Vector3.ZERO, 0.1)
	_check(grace.was_thrown(), "a launched robot reads as thrown")
	await _wait(EnemyBase.THROWN_GRACE + 0.5)
	_check(is_instance_valid(grace) and not grace.was_thrown(), "and stops THROWN_GRACE after the throw")

	# Blasts throw robots.
	var thrown := _robot(Vector3(40, 0.1, 0))
	var heavy := _robot(Vector3(40, 0.1, 10))
	var onlooker := _robot(Vector3(40, 0.1, 20))
	var robot_thrower := _robot(Vector3(30, 0.1, 20))
	await _wait(0.2)
	for e: EnemyBase in [thrown, heavy, onlooker, robot_thrower]:
		e.hp.max_health = 5000.0
		e.hp.current_health = 5000.0
	heavy.score_value = 1000
	heavy.set_physics_process(false)
	onlooker.set_physics_process(false)
	robot_thrower.set_physics_process(false)
	var x0 := thrown.global_position.x
	_grenade(Vector3(38.5, 0.3, 0), _shooter)
	_check(thrown.is_launched(), "a player grenade 1.5 m away throws a robot")
	_grenade(Vector3(38.5, 0.3, 10), _shooter)
	_check(not heavy.is_launched(), "a boss-sized robot is not thrown")
	_grenade(Vector3(38.5, 0.3, 20), robot_thrower)
	_check(not onlooker.is_launched(), "a grenade a robot threw throws nobody")
	await _wait(1.2)
	var dx := thrown.global_position.x - x0
	_check(dx >= 2.0, "the thrown robot lands at least 2 m further off", "%.1f m" % dx)

	# The headline: blast a robot off the shore into the bed.
	var kills_before := _kills.size()
	var victim := _robot(Vector3(-4.6, 0.1, 0))
	await _wait(0.2)
	victim.hp.max_health = 600.0
	victim.hp.current_health = 600.0
	_grenade(Vector3(-6.3, 0.3, 0), _shooter)
	_check(victim.is_launched(), "the shoreline robot is thrown")
	var t := 0.0
	while t < 2.0 and is_instance_valid(victim) and victim.is_launched():
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var landed_in := is_instance_valid(victim) and lava.robots_inside().has(victim)
	_check(landed_in, "it lands in the bed", "x %.1f" % (victim.global_position.x if is_instance_valid(victim) else NAN))
	if is_instance_valid(victim):
		victim.set_physics_process(false) # it is in; what it does next is the bed's business
	await _wait(2.5)
	_check(_dead(victim), "and melts there")
	_check(_kills.size() == kills_before + 1 and _kills[-1] == "lava", "as a lava kill", str(_kills))

	print("RESULT %s" % ("PASS" if _fail.is_empty() else "FAIL"))
	get_tree().quit(0 if _fail.is_empty() else 1)
