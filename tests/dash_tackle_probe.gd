extends Node3D
## Dash TACKLE: a robot in the dash's path is thrown along it and takes
## tackle_damage, once per robot per dash. A real player (physics on, facing
## -Z) dashes with the "dash" action on a flat floor:
##   - an android 1.6 m ahead is launched and takes tackle_damage exactly once,
##     and the first tackle teaches the rule once;
##   - an android 3 m to the side is untouched;
##   - a boss-sized android ahead takes the hit but is not launched;
##   - a drone ahead is untouched;
##   - a dash into an android standing 0.7 m from a lava shore lands it in the
##     bed, where it melts as a lava environmental kill.
##   godot --headless --path . --audio-driver Dummy res://tests/dash_tackle_probe.tscn

const ANDROID := preload("res://scenes/enemies/android.tscn")
const DRONE := preload("res://scenes/enemies/drone.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _fail: Array[String] = []
var _hints: Array[String] = []
var _kills: Array[String] = []
var _player: CharacterBody3D

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

func _robot(pos: Vector3, scene: PackedScene = ANDROID, health: float = 5000.0) -> EnemyBase:
	var e: EnemyBase = scene.instantiate()
	add_child(e)
	e.global_position = pos
	e.set_physics_process(false)
	await _wait(0.2)
	e.hp.max_health = health
	e.hp.current_health = health
	e.set_physics_process(true)
	return e

## Put the player at `pos` facing -Z and start a dash forward; returns as the
## dash begins (callers watch its 0.16 s themselves).
func _dash_from(pos: Vector3) -> void:
	_player.global_position = pos
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_player.set("_dash_cd", 0.0)
	await get_tree().physics_frame
	Input.action_press("dash")
	await get_tree().physics_frame
	Input.action_release("dash")

func _taken(e: EnemyBase) -> float:
	return e.hp.max_health - e.hp.current_health if is_instance_valid(e) else INF

func _run() -> void:
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(400, 1, 400)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	_player = PLAYER_SCENE.instantiate()
	add_child(_player)
	_player.global_position = Vector3(0, 0.1, 0)
	GameState.set_state(GameState.State.PLAYING)
	GameState._taught.erase("tackle")
	GameState.teach_hint.connect(func(t: String) -> void: _hints.append(t))
	GameState.environmental_kill.connect(func(k: String, _p: Vector3) -> void: _kills.append(k))
	await _wait(0.3)

	# Ahead and to the side.
	var ahead := await _robot(Vector3(0, 0.1, -1.6))
	var side := await _robot(Vector3(3, 0.1, -1.6))
	var hits := [0]
	ahead.hp.damaged.connect(func(_a: float, s: Node) -> void:
		if s == _player:
			hits[0] += 1)
	var launched := false
	await _dash_from(Vector3(0, 0.1, 0))
	var t := 0.0
	while t < 0.5:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if is_instance_valid(ahead) and ahead.is_launched():
			launched = true
	_check(launched, "a robot ahead of the dash is thrown")
	_check(_taken(ahead) >= float(_player.get("tackle_damage")) - 0.5 and hits[0] == 1,
			"it takes tackle_damage exactly once", "%.0f in %d hit(s)" % [_taken(ahead), hits[0]])
	_check(_taken(side) == 0.0, "a robot 3 m to the side is untouched", "%.0f" % _taken(side))
	_check(_hints.count(GameState.MECHANIC_HINTS["tackle"]) == 1, "the first tackle teaches the rule once", str(_hints.size()))
	for e: EnemyBase in [ahead, side]:
		e.queue_free()

	# A boss and a flyer.
	var boss := await _robot(Vector3(30, 0.1, -1.6), ANDROID, 900.0)
	boss.score_value = 1000
	var boss_flew := false
	await _dash_from(Vector3(30, 0.1, 0))
	t = 0.0
	while t < 0.5:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if boss.is_launched():
			boss_flew = true
	_check(_taken(boss) > 0.0 and not boss_flew, "a boss-sized robot takes the hit but is not thrown",
			"took %.0f, flew %s" % [_taken(boss), boss_flew])
	boss.queue_free()
	var flyer := await _robot(Vector3(60, 0.3, -1.6), DRONE)
	await _dash_from(Vector3(60, 0.1, 0))
	await _wait(0.5)
	_check(_taken(flyer) == 0.0, "a drone ahead is untouched", "%.0f" % _taken(flyer))
	flyer.queue_free()

	# Into the lava: the bed spans z -8..-4; the robot stands 0.7 m off its shore.
	var bed := LavaHazard.new()
	bed.size = Vector2(8.0, 4.0)
	add_child(bed)
	bed.global_position = Vector3(100, 0, -6)
	var victim := await _robot(Vector3(100, 0.1, -3.3), ANDROID, 110.0)
	await _dash_from(Vector3(100, 0.1, -1.0))
	await _wait(0.3)
	t = 0.0
	while t < 1.5 and is_instance_valid(victim) and victim.is_launched():
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var landed_in := is_instance_valid(victim) and bed.robots_inside().has(victim)
	_check(landed_in, "a tackle off the shore lands the robot in the bed",
			"z %.1f" % (victim.global_position.z if is_instance_valid(victim) else NAN))
	if is_instance_valid(victim):
		victim.set_physics_process(false)
	await _wait(2.0)
	_check(not is_instance_valid(victim) or not victim.hp.is_alive(), "where it melts")
	_check(_kills.size() == 1 and _kills[0] == "lava", "as a lava environmental kill", str(_kills))

	print("RESULT %s" % ("PASS" if _fail.is_empty() else "FAIL"))
	get_tree().quit(0 if _fail.is_empty() else 1)
