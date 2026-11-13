extends Node3D
## Probe: the CX-4 Cascade's alt-fire, DETONATE (WeaponData.AltMode.DETONATE).
## The Cascade had no secondary fire (#496). Its rounds prime a robot, and a
## primed robot only goes off if it dies inside Cascade.PRIME_TIME. A tap of
## alt-fire spends DETONATE_COST rounds to set off every live charge now, with
## the robot still standing: the robot and its neighbours take the blast, and
## are primed one generation deeper as in any cascade. With real androids
## (110 HP) and the real weapon scene:
##   - the Cascade's alt mode is DETONATE and the HUD tag needs DETONATE_COST;
##   - a tap with nothing primed spends nothing;
##   - with one robot primed, a tap spends DETONATE_COST rounds;
##   - the primed robot takes the charge's damage once, and so does a robot
##     3 m from it; a robot 20 m away takes nothing;
##   - both robots hit are left primed, and the gun rests DETONATE_REST;
##   - a second tap kills both (their softer charges go off on each other);
##   - a tap on DETONATE_COST - 1 rounds spends nothing and hurts nothing;
##   - a charge that has run out is not set off, and nothing is spent.
##   godot --headless --path . --audio-driver Dummy res://tests/cascade_detonate_probe.tscn

const GUN := "res://scenes/weapons/cascade.tscn"
const ANDROID := "res://scenes/enemies/android.tscn"

var ok := true
var w: Weapon
var cam: Camera3D
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
	w.try_alt_fire(alt, delta, cam, null)
	w.try_fire(false, false, cam, null)

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
	# AI off, collision on (as tests/cascade_probe does).
	e.set("disable_mode", CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE)
	e.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(e)
	e.global_position = pos
	e.process_mode = Node.PROCESS_MODE_INHERIT
	e.set_physics_process(false)
	return e

func _health(e: Node3D) -> float:
	if not is_instance_valid(e):
		return 0.0
	var d := e.get_node_or_null("Damageable") as Damageable
	return maxf(d.current_health, 0.0) if d != null else 0.0

func _alive(e: Node3D) -> bool:
	if not is_instance_valid(e):
		return false
	var d := e.get_node_or_null("Damageable") as Damageable
	return d != null and d.is_alive()

func _num(c: String) -> float:
	return float(w.get(c)) if w.get(c) != null else -1.0

func _run() -> void:
	GameState.reset_run()
	GameState.set_state(GameState.State.PLAYING)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(120, 1, 120)
	cs.shape = sh
	floor_body.add_child(cs)
	add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)
	var a := _robot(Vector3(0, 0.05, -6))
	var b := _robot(Vector3(3, 0.05, -6))
	var far := _robot(Vector3(20, 0.05, -6))
	cam = Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 1.6, 0)
	var scene := (load(GUN) as PackedScene).instantiate()
	cam.add_child(scene)
	await get_tree().process_frame
	await _wait(0.4)
	w = scene as Weapon
	w.reserve = 0
	w.mag = w.data.mag_size
	var cost := int(_num("DETONATE_COST"))
	var rest := _num("DETONATE_REST")
	var dmg := w.data.cascade_damage
	var radius := w.data.cascade_radius
	var full := _health(a)
	var mode_name: String = WeaponData.AltMode.keys()[int(w.data.alt_mode)]
	_check("the Cascade's alt mode is DETONATE", mode_name == "DETONATE", mode_name)
	_check("a detonation costs 4 of 22 rounds; a charge is 70 damage over 5 m; an android has 110 HP", cost == 4 and w.alt_cost() == 4 and w.data.mag_size == 22 and is_equal_approx(dmg, 70.0) and is_equal_approx(radius, 5.0) and is_equal_approx(full, 110.0), "cost %d, alt_cost %d, %.0f over %.0f m, %.0f HP" % [cost, w.alt_cost(), dmg, radius, full])

	await _tap()
	_check("a tap with nothing primed spends nothing", w.mag == 22 and is_equal_approx(_health(a), full), "%d left, A %.0f" % [w.mag, _health(a)])

	Cascade.prime(a, dmg, radius, null)
	_check("a cascade charge primes the robot", Cascade.is_primed(a) and not Cascade.is_primed(b))
	w._cooldown = 0.0
	await _tap()
	var cd := w._cooldown
	await _wait(0.6)
	_check("with one robot primed, a tap spends DETONATE_COST rounds", w.mag == 18, "%d left" % w.mag)
	_check("the primed robot takes the charge once, still standing", _alive(a) and is_equal_approx(_health(a), full - dmg), "%.0f of %.0f" % [_health(a), full])
	_check("a robot 3 m from it takes the blast too", _alive(b) and is_equal_approx(_health(b), full - dmg), "%.0f of %.0f" % [_health(b), full])
	_check("a robot 20 m away takes nothing", is_equal_approx(_health(far), full), "%.0f" % _health(far))
	_check("both robots hit are left primed", Cascade.is_primed(a) and Cascade.is_primed(b) and not Cascade.is_primed(far))
	_check("the gun rested DETONATE_REST", rest > 0.3 and cd > rest - 0.3 and cd <= rest, "cooldown %.2f s of %.2f" % [cd, rest])

	await _wait(maxf(rest, 0.0))
	w._cooldown = 0.0
	await _tap()
	await _wait(1.0)
	_check("a second tap kills both", w.mag == 14 and not _alive(a) and not _alive(b), "%d left, A %.0f, B %.0f" % [w.mag, _health(a), _health(b)])
	_check("and the robot 20 m away is still untouched", is_equal_approx(_health(far), full), "%.0f" % _health(far))

	w._cooldown = 0.0
	w.mag = maxi(cost, 1) - 1
	var left := w.mag
	Cascade.prime(far, dmg, radius, null)
	await _tap()
	await _wait(0.5)
	_check("a tap on DETONATE_COST - 1 rounds spends nothing and hurts nothing", w.mag == left and is_equal_approx(_health(far), full) and cost > 0, "%d left, %.0f" % [w.mag, _health(far)])

	w.mag = w.data.mag_size
	w._cooldown = 0.0
	await _wait(Cascade.PRIME_TIME + 0.1)
	await _tap()
	await _wait(0.5)
	_check("a charge that has run out is not set off, and nothing is spent", w.mag == w.data.mag_size and is_equal_approx(_health(far), full) and not Cascade.is_primed(far), "%d left, %.0f" % [w.mag, _health(far)])

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
