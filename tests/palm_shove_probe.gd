extends Node3D
## Probe: the PALM Cannon's alt-fire, SHOVE (WeaponData.AltMode.SHOVE).
## The PALM Cannon was the last gun with no secondary fire (#496). A tap spends
## SHOVE_COST bolts on an open-palm blast: every robot within SHOVE_RANGE and
## SHOVE_HALF_ANGLE of where the player faces, that no world geometry hides,
## takes SHOVE_DAMAGE and is thrown away from the player (BlastPush.throw, so
## flyers and bosses take the damage and stay put). The gun then rests
## SHOVE_REST seconds. With real androids and the real weapon scene:
##   - the PALM Cannon's alt mode is SHOVE and the HUD tag needs SHOVE_COST;
##   - a tap spends SHOVE_COST bolts;
##   - a robot 4 m in front takes SHOVE_DAMAGE and is thrown up and away;
##   - a robot 4 m away but 60 degrees off the aim is untouched, and so are
##     one 8 m in front and one 5 m away behind a wall;
##   - the gun rests SHOVE_REST, and a tap on SHOVE_COST - 1 bolts does nothing.
##   godot --headless --path . --audio-driver Dummy res://tests/palm_shove_probe.tscn

const GUN := "res://scenes/weapons/salvage_palm.tscn"
const ANDROID := "res://scenes/enemies/android.tscn"

var ok := true
var w: Weapon
var cam: Camera3D
var shooter: Node3D
var alt := false
var clock := 0.0

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _process(delta: float) -> void:
	clock += delta
	if w == null:
		return
	w.try_alt_fire(alt, delta, cam, shooter)
	w.try_fire(false, false, cam, shooter)

func _wait(sec: float) -> void:
	var until := clock + sec
	while clock < until:
		await get_tree().process_frame

func _tap() -> void:
	alt = true
	await _wait(0.06)
	alt = false
	await _wait(0.06)

func _robot(pos: Vector3) -> Node3D:
	var e := (load(ANDROID) as PackedScene).instantiate() as Node3D
	# AI off, collision on (as tests/cascade_probe does). A throw then only sets
	# the robot's velocity: it does not move, so the checks read the throw itself.
	e.set("disable_mode", CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE)
	e.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(e)
	e.global_position = pos
	e.process_mode = Node.PROCESS_MODE_INHERIT
	e.set_physics_process(false)
	return e

func _health(e: Node3D) -> float:
	return (e.get_node("Damageable") as Damageable).current_health

func _thrown(e: Node3D) -> bool:
	return bool(e.call("is_launched"))

func _box(size: Vector3, pos: Vector3) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	add_child(b)
	b.global_position = pos

func _num(c: String) -> float:
	return float(w.get(c)) if w.get(c) != null else -1.0

func _run() -> void:
	GameState.reset_run()
	GameState.set_state(GameState.State.PLAYING)
	_box(Vector3(120, 1, 120), Vector3(0, -0.5, 0))
	_box(Vector3(0.6, 4, 0.3), Vector3(1.3, 2, -2.8)) # hides the robot at (2.1, -4.5)
	var front := _robot(Vector3(0, 0.05, -4))
	var side := _robot(Vector3(-3.46, 0.05, -2))   # 4 m away, 60 degrees off the aim
	var far := _robot(Vector3(0, 0.05, -8))
	var walled := _robot(Vector3(2.1, 0.05, -4.5)) # 5 m away, 25 degrees off, behind the wall
	shooter = Node3D.new()
	shooter.add_to_group("player")
	add_child(shooter)
	cam = Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 1.6, 0)
	var scene := (load(GUN) as PackedScene).instantiate()
	cam.add_child(scene)
	await get_tree().process_frame
	await _wait(0.4)
	w = scene as Weapon
	w.mag = w.data.mag_size
	w._cooldown = 0.0
	var cost := int(_num("SHOVE_COST"))
	var reach := _num("SHOVE_RANGE")
	var half := _num("SHOVE_HALF_ANGLE")
	var dmg := _num("SHOVE_DAMAGE")
	var rest := _num("SHOVE_REST")
	var full := _health(front)
	var mode_name: String = WeaponData.AltMode.keys()[int(w.data.alt_mode)]
	_check("the PALM Cannon's alt mode is SHOVE", mode_name == "SHOVE", mode_name)
	_check("a shove costs 4 of 16 bolts, reaches 6 m and 35 degrees each side, deals 30", cost == 4 and w.alt_cost() == 4 and w.data.mag_size == 16 and is_equal_approx(reach, 6.0) and is_equal_approx(half, 35.0) and is_equal_approx(dmg, 30.0), "cost %d, alt_cost %d, %.1f m, %.0f deg, %.0f" % [cost, w.alt_cost(), reach, half, dmg])

	await _tap()
	var cd := w._cooldown
	var v: Vector3 = front.get("velocity")
	_check("a tap spends SHOVE_COST bolts", w.mag == 12, "%d left" % w.mag)
	_check("a robot 4 m in front takes SHOVE_DAMAGE", is_equal_approx(full - _health(front), dmg) and dmg > 0.0, "%.0f of %.0f" % [_health(front), full])
	_check("and is thrown up and away from the player", _thrown(front) and v.z < -3.0 and v.y > 2.0 and absf(v.x) < 0.5, "velocity %s" % str(v.snapped(Vector3.ONE * 0.1)))
	_check("a robot 4 m away, 60 degrees off the aim, is untouched", is_equal_approx(_health(side), full) and not _thrown(side), "%.0f" % _health(side))
	_check("a robot 8 m in front is untouched", is_equal_approx(_health(far), full) and not _thrown(far), "%.0f" % _health(far))
	_check("a robot 5 m away behind a wall is untouched", is_equal_approx(_health(walled), full) and not _thrown(walled), "%.0f" % _health(walled))
	_check("the gun rested SHOVE_REST", rest > 0.3 and cd > rest - 0.3 and cd <= rest, "cooldown %.2f s of %.2f" % [cd, rest])

	await _wait(maxf(rest, 0.0))
	w._cooldown = 0.0
	w.mag = maxi(cost, 1) - 1
	var left := w.mag
	var before := _health(front)
	await _tap()
	_check("a tap on SHOVE_COST - 1 bolts does nothing", w.mag == left and is_equal_approx(_health(front), before) and cost > 0, "%d left, %.0f" % [w.mag, _health(front)])

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
