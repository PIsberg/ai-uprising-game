extends Node3D
## Probe: the MK-VII Longshot's alt-fire, PUNCH-THROUGH (WeaponData.AltMode.PUNCH,
## Weapon._do_hitscan with _alt_punch). The Longshot had no secondary fire
## (#496). Through the real weapon scene, driven the way WeaponManager drives it,
## at a lane of walls (world, layer 1) and plates (Damageable, layer 4):
##   - the Longshot's alt mode is PUNCH and one use costs 3 rounds;
##   - a trigger round stops at the first wall: the plate behind it takes nothing;
##   - a tap fires one slug for 3 rounds, dead straight from the hip, and it
##     goes through PUNCH_WALLS walls: the plate behind the first takes
##     PUNCH_KEEP of the gun's damage, the one behind the second PUNCH_KEEP
##     squared, the one behind the third nothing;
##   - each wall it crosses gets a hole where the slug went in and one where it
##     came out;
##   - a wall thicker than PUNCH_THICK stops it (the 3 rounds are spent);
##   - the slug goes through every robot on its line, where a trigger round
##     stops after the gun's `pierce`;
##   - holding the button fires one slug only;
##   - after a slug the trigger waits PUNCH_REST of the gun's shot intervals;
##   - with two rounds left the tap fires nothing and keeps them.
## Timed on summed process deltas.
##   godot --headless --path . --audio-driver Dummy res://tests/punch_through_probe.tscn

const WALL_THICK := 0.6

var ok := true
var w: Weapon
var cam: Camera3D
var mode := "" ## "alt" (button held), "hip" (trigger pulled), "": what _process holds down
var clock := 0.0
var tick := 0
var shots: Array = [] ## [clock, cone in degrees] per round fired
var hits := {} ## plate name -> Array of damage amounts
var rig: Node3D

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
	w.try_alt_fire(mode == "alt", delta, cam, null)
	# A semi-auto wants a fresh pull per round: squeeze on alternate frames.
	tick += 1
	w.try_fire(mode == "hip" and tick % 2 == 0, false, cam, null)

func _wait(sec: float) -> void:
	var until := clock + sec
	while clock < until:
		await get_tree().process_frame

## One press of the alt-fire button, let go again.
func _tap() -> void:
	mode = "alt"
	await _wait(0.05)
	mode = ""

## One pull of the trigger.
func _pull() -> void:
	var n := shots.size()
	mode = "hip"
	while shots.size() == n and w.mag > 0:
		await get_tree().process_frame
	mode = ""

func _load() -> void:
	mode = ""
	w._reloading = false
	w._cooldown = 0.0
	w.mag = w.data.mag_size
	shots.clear()
	hits.clear()
	for h in get_tree().get_nodes_in_group("bullet_hole"):
		h.free()

func _wall(z: float, thick: float = WALL_THICK) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 6.0, thick)
	cs.shape = box
	body.add_child(cs)
	rig.add_child(body)
	body.global_position = Vector3(0, 2.0, z)

func _plate(label: String, z: float) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 4
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 4.0, 0.3)
	cs.shape = box
	body.add_child(cs)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 1000000.0
	body.add_child(hp)
	rig.add_child(body)
	body.global_position = Vector3(0, 2.0, z)
	hp.current_health = 1000000.0
	hp.damaged.connect(func(amount: float, _src: Node) -> void:
		if not hits.has(label):
			hits[label] = []
		(hits[label] as Array).append(amount))

func _new_rig() -> void:
	if rig:
		rig.free()
	rig = Node3D.new()
	add_child(rig)

func _settle() -> void:
	for i in 3:
		await get_tree().physics_frame

func _took(label: String) -> float:
	var total := 0.0
	for a in hits.get(label, []):
		total += float(a)
	return total

func _holes_near(z: float) -> int:
	var n := 0
	for h in get_tree().get_nodes_in_group("bullet_hole"):
		if absf((h as Node3D).global_position.z - z) < 0.06:
			n += 1
	return n

func _const(c: String) -> float:
	return float(w.get(c)) if w.get(c) != null else 0.0

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	# Bullet marks are the channel for the entry and exit holes, and are
	# skipped below MEDIUM detail (BulletMark.spawn).
	GraphicsSettings.set_quality(2)
	cam = Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 1.6, 0)
	var scene := (load("res://scenes/weapons/sniper.tscn") as PackedScene).instantiate()
	cam.add_child(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	w = scene as Weapon
	w.fired.connect(func(_w: Weapon) -> void: shots.append([clock, w.shot_spread_deg(false, null)]))
	var d := w.data
	var interval := 1.0 / d.fire_rate
	var keep := _const("PUNCH_KEEP")
	var thick := _const("PUNCH_THICK")
	var walls := int(_const("PUNCH_WALLS"))
	var rest := _const("PUNCH_REST")
	var mode_name: String = WeaponData.AltMode.keys()[int(d.alt_mode)]
	_check("the Longshot's alt mode is PUNCH", mode_name == "PUNCH", mode_name)
	_check("one use costs 3 rounds", int(w.alt_cost()) == 3, str(w.alt_cost()))
	_check("a slug goes through 2 walls up to 2.5 m thick and keeps 0.75 of its damage per wall", walls == 2 and is_equal_approx(thick, 2.5) and is_equal_approx(keep, 0.75), "%d walls, %.2f m, %.2f" % [walls, thick, keep])

	# Lane 1: wall, plate, wall, plate, wall, plate. Everything is past the
	# Longshot's 25 m close band, so range does not scale the damage.
	_new_rig()
	_wall(-30.0)
	_plate("A", -40.0)
	_wall(-50.0)
	_plate("B", -60.0)
	_wall(-70.0)
	_plate("C", -80.0)
	await _settle()

	seed(7)
	_load()
	await _wait(0.3)
	await _pull()
	await _wait(0.2)
	_check("a trigger round stops at the first wall", shots.size() == 1 and _took("A") == 0.0 and _took("B") == 0.0, "A took %.1f" % _took("A"))

	_load()
	await _wait(0.3)
	await _tap()
	await _wait(0.3)
	_check("a tap fires one slug and takes 3 from the magazine", shots.size() == 1 and w.mag == d.mag_size - 3, "%d fired, %d left of %d" % [shots.size(), w.mag, d.mag_size])
	if shots.size() == 1:
		_check("dead straight from the hip", float(shots[0][1]) == 0.0, "%s degrees" % shots[0][1])
	_check("the plate behind the first wall takes PUNCH_KEEP of the gun's damage", keep > 0.0 and absf(_took("A") - d.damage * keep) < 0.5, "%.1f against %.1f" % [_took("A"), d.damage * keep])
	_check("the plate behind the second wall takes PUNCH_KEEP squared", keep > 0.0 and absf(_took("B") - d.damage * keep * keep) < 0.5, "%.1f against %.1f" % [_took("B"), d.damage * keep * keep])
	_check("the plate behind the third wall takes nothing", _took("C") == 0.0, "%.1f" % _took("C"))
	var half := WALL_THICK * 0.5
	_check("the first wall has a hole where the slug went in and one where it came out", _holes_near(-30.0 + half) == 1 and _holes_near(-30.0 - half) == 1, "in %d, out %d" % [_holes_near(-30.0 + half), _holes_near(-30.0 - half)])
	_check("so has the second", _holes_near(-50.0 + half) == 1 and _holes_near(-50.0 - half) == 1, "in %d, out %d" % [_holes_near(-50.0 + half), _holes_near(-50.0 - half)])
	_check("the third has the hole it stopped in and no way out", _holes_near(-70.0 + half) == 1 and _holes_near(-70.0 - half) == 0, "in %d, out %d" % [_holes_near(-70.0 + half), _holes_near(-70.0 - half)])

	# Held.
	_load()
	await _wait(0.3)
	mode = "alt"
	await _wait(2.5)
	mode = ""
	_check("holding the button fires one slug only", shots.size() == 1 and w.mag == d.mag_size - 3, "%d fired, %d left" % [shots.size(), w.mag])

	# The rest after a slug.
	_load()
	await _wait(0.3)
	await _tap()
	await _wait(0.1)
	mode = "hip"
	while shots.size() < 2 and not shots.is_empty() and clock - float(shots[0][0]) < 4.0:
		await get_tree().process_frame
	mode = ""
	if shots.size() >= 2:
		var gap: float = float(shots[1][0]) - float(shots[0][0])
		_check("after a slug the trigger waits PUNCH_REST shot intervals", rest > 1.2 and gap > interval * rest - 0.04 and gap < interval * rest + 0.12, "%.3f s against %.3f" % [gap, interval * rest])
	else:
		_check("after a slug the trigger waits PUNCH_REST shot intervals", false, "%d rounds fired" % shots.size())

	# Two rounds left.
	_load()
	w.mag = 2
	await _wait(0.3)
	await _tap()
	await _wait(0.3)
	_check("with two rounds left the tap fires nothing and keeps them", shots.is_empty() and w.mag == 2, "%d fired, %d left" % [shots.size(), w.mag])

	# Lane 2: a wall thicker than the slug can cross.
	_new_rig()
	_wall(-32.0, thick + 1.5)
	_plate("D", -45.0)
	await _settle()
	_load()
	await _wait(0.3)
	await _tap()
	await _wait(0.3)
	_check("a wall thicker than PUNCH_THICK stops the slug, and the 3 rounds are spent", shots.size() == 1 and _took("D") == 0.0 and w.mag == d.mag_size - 3, "D took %.1f, %d left" % [_took("D"), w.mag])

	# Lane 3: a wall just inside the limit.
	_new_rig()
	_wall(-32.0, thick - 0.3)
	_plate("E", -45.0)
	await _settle()
	_load()
	await _wait(0.3)
	await _tap()
	await _wait(0.3)
	_check("a wall 0.3 m inside the limit does not", keep > 0.0 and absf(_took("E") - d.damage * keep) < 0.5, "E took %.1f" % _took("E"))

	# Lane 4: five robots in a row, no wall.
	_new_rig()
	for i in 5:
		_plate("R%d" % i, -30.0 - 4.0 * i)
	await _settle()
	_load()
	await _wait(0.3)
	await _pull()
	await _wait(0.2)
	var by_trigger := hits.size()
	_load()
	await _wait(0.3)
	await _tap()
	await _wait(0.3)
	_check("a trigger round stops after the gun's pierce", by_trigger == d.pierce + 1 and by_trigger < 5, "%d of 5 hit, pierce %d" % [by_trigger, d.pierce])
	_check("the slug goes through every robot on its line at full damage", hits.size() == 5 and absf(_took("R4") - d.damage) < 0.5, "%d of 5 hit, the last took %.1f" % [hits.size(), _took("R4")])

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
