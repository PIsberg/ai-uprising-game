extends Node3D
## Scrap physics: a thrown robot (EnemyBase.launch, as BlastPush and a Bumper
## throw it) is a projectile. On a flat floor with a wall and an 8 m ledge:
##   - an android launched at 9 m/s (5 m/s up, so it reaches the wall 3 m off) takes the impact (at least 30:
##     IMPACT_DMG_PER_MS x the speed) and its flight ends short of the wall;
##   - launched into a second android it bowls it over: the second is launched
##     and hurt and flies on past where it stood, the first is hurt too;
##   - a boss-sized android in the path takes the hit but is not launched;
##   - an android falling 7 m takes 50 to 90 (FALL_DMG_PER_M past FALL_FREE_M);
##     one falling 2.5 m takes nothing;
##   - a 20 HP android into the wall and a 30 HP one dropped 10 m die as "impact"
##     and "fall" environmental kills, each paying SCRAP_BONUS on top of the
##     kill, counted as scrapped (not meltdowns), teaching the rule once;
##   - a robot thrown off the ledge with a 0.3 s throw is still flying at 0.7 s
##     (it flies until it lands) and takes the drop.
##   godot --headless --path . --audio-driver Dummy res://tests/scrap_physics_probe.tscn

const ANDROID := preload("res://scenes/enemies/android.tscn")
const WALL_X := 10.0

var _fail: Array[String] = []
var _kills: Array[String] = []
var _hints: Array[String] = []

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

func _box(pos: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	add_child(b)
	b.global_position = pos

## A held android (physics off) at `pos`, stats synced, `hp` health.
func _robot(pos: Vector3, health: float = 110.0) -> EnemyBase:
	var e: EnemyBase = ANDROID.instantiate()
	add_child(e)
	e.global_position = pos
	e.set_physics_process(false)
	await _wait(0.2)
	e.hp.max_health = health
	e.hp.current_health = health
	return e

## Release and throw it.
func _throw(e: EnemyBase, v: Vector3, seconds: float = 1.0) -> void:
	e.set_physics_process(true)
	e.launch(v, seconds)

## Wait until the throw is over (or `max_t`), then hold it where it ended.
func _until_landed(e: EnemyBase, max_t: float) -> float:
	var t := 0.0
	while t < max_t and is_instance_valid(e) and e.is_launched():
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	if is_instance_valid(e):
		e.set_physics_process(false)
	return t

func _taken(e: EnemyBase) -> float:
	return e.hp.max_health - e.hp.current_health if is_instance_valid(e) else INF

func _dead(e: EnemyBase) -> bool:
	return not is_instance_valid(e) or not e.hp.is_alive()

func _run() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(400, 1, 400))
	_box(Vector3(WALL_X, 3, 0), Vector3(1, 6, 40))      # the wall, x 9.5..10.5, z -20..20
	_box(Vector3(60, 4, 0), Vector3(6, 8, 6))           # the ledge, top at y 8, x 57..63
	GameState.set_state(GameState.State.PLAYING)
	GameState._taught.erase("scrapped")
	GameState.stat_scrapped = 0
	GameState.stat_meltdowns = 0
	GameState.environmental_kill.connect(func(k: String, _p: Vector3) -> void: _kills.append(k))
	GameState.teach_hint.connect(func(t: String) -> void: _hints.append(t))

	# Into the wall.
	var a := await _robot(Vector3(6.5, 0.1, 0))
	_throw(a, Vector3(9, 5, 0))
	await _until_landed(a, 1.5)
	_check(_taken(a) >= 30.0, "an android thrown into a wall at 9 m/s takes the impact", "%.0f" % _taken(a))
	_check(is_instance_valid(a) and a.global_position.x < WALL_X - 0.4 and not a.is_launched(),
			"its flight ends at the wall", "x %.2f" % a.global_position.x)

	# Bowling.
	var b := await _robot(Vector3(20, 0.1, -10))
	var c := await _robot(Vector3(22.2, 0.1, -10))
	c.set_physics_process(true)
	_throw(b, Vector3(9, 2.5, 0))
	var t := 0.0
	var c_flew := false
	while t < 0.6:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if c.is_launched():
			c_flew = true
	_check(c_flew, "a robot in the path is bowled over (launched)")
	await _until_landed(c, 1.5)
	await _until_landed(b, 1.5)
	_check(_taken(c) > 0.0, "the bowled robot is hurt", "%.0f" % _taken(c))
	_check(_taken(b) > 0.0, "the flier is hurt by the hit too", "%.0f" % _taken(b))
	_check(is_instance_valid(c) and c.global_position.x > 23.2, "the bowled robot flies on past where it stood",
			"x %.2f" % (c.global_position.x if is_instance_valid(c) else NAN))
	var b2 := await _robot(Vector3(20, 0.1, 10))
	var boss := await _robot(Vector3(22.2, 0.1, 10), 900.0)
	boss.score_value = 1000
	boss.set_physics_process(true)
	_throw(b2, Vector3(9, 2.5, 0))
	t = 0.0
	var boss_flew := false
	while t < 0.6:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if boss.is_launched():
			boss_flew = true
	await _until_landed(b2, 1.5)
	boss.set_physics_process(false)
	_check(_taken(boss) > 0.0 and not boss_flew, "a boss-sized robot takes the hit but is not launched",
			"took %.0f, flew %s" % [_taken(boss), boss_flew])

	# Falls.
	var e := await _robot(Vector3(40, 7.0, 0))
	var f := await _robot(Vector3(45, 2.5, 0))
	_throw(e, Vector3(0.3, 0, 0))
	_throw(f, Vector3(0.3, 0, 0))
	await _until_landed(e, 2.0)
	await _until_landed(f, 2.0)
	_check(_taken(e) >= 50.0 and _taken(e) <= 90.0, "an android falling 7 m takes the drop", "%.0f" % _taken(e))
	_check(_taken(f) == 0.0, "one falling 2.5 m takes nothing", "%.0f" % _taken(f))

	# Kills.
	var score0 := GameState.score
	var g := await _robot(Vector3(40, 10.5, 10), 30.0)
	var h := await _robot(Vector3(6.5, 0.1, 15), 20.0)
	_throw(g, Vector3(0.3, 0, 0))
	_throw(h, Vector3(9, 5, 0))
	await _wait(1.6)
	_check(_dead(g), "a 30 HP android dropped 10 m dies")
	_check(_dead(h), "a 20 HP android thrown into the wall dies")
	_check(_kills.size() == 2 and _kills.has("fall") and _kills.has("impact"),
			"both are environmental kills of their kind", str(_kills))
	_check(GameState.stat_scrapped == 2 and GameState.stat_meltdowns == 0,
			"both count as scrapped, not meltdowns", "%d / %d" % [GameState.stat_scrapped, GameState.stat_meltdowns])
	_check(GameState.score - score0 >= 2 * (GameState.SCRAP_BONUS + 150),
			"both pay SCRAP_BONUS on top of the kill", "+%d" % (GameState.score - score0))
	_check(_hints.count(GameState.MECHANIC_HINTS["scrapped"]) == 1, "the first teaches the rule once", str(_hints.size()))

	# Off the ledge: a short throw still flies until it lands.
	var i := await _robot(Vector3(62.5, 8.1, 0))
	_throw(i, Vector3(6, 1, 0), 0.3)
	await _wait(0.7)
	_check(is_instance_valid(i) and i.is_launched() and i.global_position.y > 1.0,
			"a robot thrown off the ledge is still flying at 0.7 s", "y %.2f" % i.global_position.y)
	await _until_landed(i, 2.0)
	_check(_taken(i) >= 50.0, "and takes the drop when it lands", "%.0f" % _taken(i))

	print("RESULT %s" % ("PASS" if _fail.is_empty() else "FAIL"))
	get_tree().quit(0 if _fail.is_empty() else 1)
