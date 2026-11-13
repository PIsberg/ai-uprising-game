extends Node3D
## Probe: the VK-7 Tesla Projector's alt-fire, NOVA (WeaponData.AltMode.NOVA).
## The Tesla had no secondary fire (#496). Its beam reaches 13 m and holds one
## robot; a tap of alt-fire dumps NOVA_COST cells into a ring around the
## player: every robot within NOVA_RADIUS that the player can see takes
## NOVA_DAMAGE and is switched off for NOVA_STUN (EnemyBase.emp_disable), and
## the gun rests NOVA_REST seconds. Through the real weapon scene:
##   - the Tesla's alt mode is NOVA and the HUD tag needs NOVA_COST cells;
##   - a tap on a full magazine spends NOVA_COST cells;
##   - a robot 4 m in front takes NOVA_DAMAGE, and so does one 6 m BEHIND;
##   - both are switched off for NOVA_STUN;
##   - a robot 9 m away takes nothing, and neither does one 5 m away behind a wall;
##   - the gun then rests NOVA_REST, and a second tap inside the rest does nothing;
##   - a tap on NOVA_COST - 1 cells does nothing;
##   - a real android in reach loses health and is switched off.
##   godot --headless --path . --audio-driver Dummy res://tests/nova_fire_probe.tscn

const GUN := "res://scenes/weapons/tesla.tscn"
const ANDROID := "res://scenes/enemies/android.tscn"

class Dummy extends StaticBody3D:
	var stuns: Array = []
	func emp_disable(duration: float) -> void:
		stuns.append(duration)

var ok := true
var w: Weapon
var cam: Camera3D
var alt := false
var clock := 0.0
var hurt := {}

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

func _box(body: StaticBody3D, size: Vector3, pos: Vector3, layer: int) -> void:
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	add_child(body)
	body.global_position = pos

## A stand-in robot with its origin at its feet, like the real ones.
func _robot(tag: String, at: Vector3) -> Dummy:
	var b := Dummy.new()
	b.collision_layer = 4
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.8, 1.8, 0.8)
	cs.shape = sh
	cs.position = Vector3(0, 0.9, 0)
	b.add_child(cs)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 1000000.0
	b.add_child(hp)
	hp.current_health = 1000000.0
	hurt[tag] = []
	hp.damaged.connect(func(amount: float, _src: Node) -> void: (hurt[tag] as Array).append(amount))
	add_child(b)
	b.global_position = at
	return b

func _sum(tag: String) -> float:
	var t := 0.0
	for a in hurt[tag]:
		t += float(a)
	return t

func _num(c: String) -> float:
	return float(w.get(c)) if w.get(c) != null else -1.0

func _run() -> void:
	GameState.reset_run()
	GameState.set_state(GameState.State.PLAYING)
	_box(StaticBody3D.new(), Vector3(80, 1, 80), Vector3(0, -0.5, 0), 1)
	_box(StaticBody3D.new(), Vector3(0.5, 4, 4), Vector3(3, 2, 0), 1) # a wall to the right
	var front := _robot("front", Vector3(0, 0, -4))
	var back := _robot("back", Vector3(0, 0, 6))
	_robot("far", Vector3(0, 0, -9))
	_robot("walled", Vector3(5, 0, 0))
	cam = Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 1.6, 0)
	var scene := (load(GUN) as PackedScene).instantiate()
	cam.add_child(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	w = scene as Weapon
	w.reserve = 0
	w.mag = w.data.mag_size
	var cost := int(_num("NOVA_COST"))
	var radius := _num("NOVA_RADIUS")
	var dmg := _num("NOVA_DAMAGE")
	var stun := _num("NOVA_STUN")
	var rest := _num("NOVA_REST")
	var mode_name: String = WeaponData.AltMode.keys()[int(w.data.alt_mode)]
	_check("the Tesla's alt mode is NOVA", mode_name == "NOVA", mode_name)
	_check("a nova costs 30 of 90 cells, reaches 7 m, deals 90 and stuns 1.5 s", cost == 30 and w.alt_cost() == 30 and w.data.mag_size == 90 and is_equal_approx(radius, 7.0) and is_equal_approx(dmg, 90.0) and is_equal_approx(stun, 1.5), "cost %d, alt_cost %d, %.1f m, %.0f, %.1f s" % [cost, w.alt_cost(), radius, dmg, stun])

	await _tap()
	_check("a tap on a full magazine spends NOVA_COST cells", w.mag == 60, "%d left" % w.mag)
	_check("a robot 4 m in front takes NOVA_DAMAGE", is_equal_approx(_sum("front"), dmg) and dmg > 0.0, "%.0f" % _sum("front"))
	_check("a robot 6 m behind the player takes it too", is_equal_approx(_sum("back"), dmg) and dmg > 0.0, "%.0f" % _sum("back"))
	_check("both are switched off for NOVA_STUN", front.stuns == [stun] and back.stuns == [stun], "front %s, back %s" % [front.stuns, back.stuns])
	_check("a robot 9 m away takes nothing", _sum("far") == 0.0, "%.0f" % _sum("far"))
	_check("a robot 5 m away behind a wall takes nothing", _sum("walled") == 0.0, "%.0f" % _sum("walled"))
	_check("the gun then rests NOVA_REST", rest > 0.5 and w._cooldown > rest - 0.3 and w._cooldown <= rest, "cooldown %.2f s of %.2f" % [w._cooldown, rest])

	await _tap()
	_check("a second tap inside the rest does nothing", w.mag == 60 and is_equal_approx(_sum("front"), dmg), "%d left, front %.0f" % [w.mag, _sum("front")])

	await _wait(maxf(rest, 0.0) + 0.2)
	w._cooldown = 0.0
	w.mag = maxi(cost, 1) - 1
	var left := w.mag
	await _tap()
	_check("a tap on NOVA_COST - 1 cells does nothing", w.mag == left and is_equal_approx(_sum("front"), dmg) and dmg > 0.0, "%d left, front %.0f" % [w.mag, _sum("front")])

	# A real robot, so the stand-ins' shape (origin at the feet, emp_disable on
	# the collider) is checked against the thing they stand in for.
	var bot := (load(ANDROID) as PackedScene).instantiate() as Node3D
	add_child(bot)
	bot.global_position = Vector3(-3, 0.1, -2)
	await _wait(0.5)
	var bhp := bot.get_node("Damageable")
	var before: float = bhp.current_health
	w._cooldown = 0.0
	w.mag = w.data.mag_size
	await _tap()
	var lost: float = before - bhp.current_health
	_check("a real android 3.6 m away loses health and is switched off", lost > 0.0 and float(bot.get("_emp_t")) > 0.0, "lost %.0f of %.0f, off for %.2f s" % [lost, before, float(bot.get("_emp_t"))])
	bot.free()

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
