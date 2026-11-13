extends Node3D
## Probe: the TPX-9 Tempest Coil's alt-fire, ARC MINE (WeaponData.AltMode.MINE).
## The Tempest had no secondary fire (#496). A tap spends MINE_COST rounds on
## an orb that sticks to the world where it lands and waits: it goes off, with
## the gun's full splash and chain lightning, when a robot comes within
## Projectile.MINE_TRIGGER of it, or by itself after Projectile.MINE_LIFE.
## Through the real weapon scene and the real projectile:
##   - the Tempest's alt mode is MINE and the HUD tag needs MINE_COST rounds;
##   - a trigger round fired at a wall goes off on it (gone within 1 s);
##   - a mine fired at the same wall spends MINE_COST rounds, is still there
##     1 s and 2 s later, at rest on the wall, with a robot 6 m away unharmed;
##   - a robot that comes within MINE_TRIGGER sets it off inside 0.4 s, takes the
##     blast, and the chain reaches a second robot 8 m from the mine;
##   - a mine left alone is still there 1 s before MINE_LIFE and gone after it;
##   - a mine round that strikes a robot directly goes off at once;
##   - a tap on fewer than MINE_COST rounds fires nothing.
## Timed on summed process deltas.
##   godot --headless --path . --audio-driver Dummy res://tests/arc_mine_probe.tscn

const GUN := "res://scenes/weapons/tempest.tscn"
const WALL_Z := -15.0 ## the wall's near face

var ok := true
var w: Weapon
var cam: Camera3D
var mode := ""
var clock := 0.0
var tick := 0
var rounds: Array = [] ## every projectile the gun has launched
var hurt := {} ## dummy name -> Array of damage amounts

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	child_entered_tree.connect(func(n: Node) -> void:
		if n is Projectile:
			rounds.append(n))
	_run.call_deferred()

func _process(delta: float) -> void:
	clock += delta
	if w == null:
		return
	w.try_alt_fire(mode == "alt", delta, cam, null)
	tick += 1
	w.try_fire(mode == "hip" and tick % 2 == 0, false, cam, null)

func _wait(sec: float) -> void:
	var until := clock + sec
	while clock < until:
		await get_tree().process_frame

func _press(m: String) -> void:
	mode = m
	await _wait(0.06)
	mode = ""

func _load(n: int) -> void:
	mode = ""
	await _wait(0.1)
	w._reloading = false
	w._cooldown = 0.0
	w.mag = n
	rounds.clear()
	hurt = {"A": [], "B": []}

func _live() -> Projectile:
	for r in rounds:
		if is_instance_valid(r) and not (r as Projectile).is_queued_for_deletion():
			return r
	return null

func _box(size: Vector3, pos: Vector3, layer: int) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	add_child(b)
	b.global_position = pos
	return b

func _robot(tag: String, pos: Vector3) -> StaticBody3D:
	var b := _box(Vector3(0.8, 1.8, 0.8), pos, 4)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 1000000.0
	b.add_child(hp)
	hp.current_health = 1000000.0
	hp.damaged.connect(func(amount: float, _src: Node) -> void: (hurt[tag] as Array).append(amount))
	return b

func _sum(tag: String) -> float:
	var t := 0.0
	for a in hurt[tag]:
		t += float(a)
	return t

## Move a dummy and let the physics server see it.
func _place(b: StaticBody3D, pos: Vector3) -> void:
	b.global_position = pos
	await get_tree().physics_frame
	await get_tree().physics_frame

func _num(obj: Object, c: String) -> float:
	return float(obj.get(c)) if obj != null and obj.get(c) != null else -1.0

func _run() -> void:
	GameState.reset_run()
	GameState.set_state(GameState.State.PLAYING)
	_box(Vector3(80, 1, 80), Vector3(0, -0.5, 0), 1)
	_box(Vector3(8, 6, 0.5), Vector3(0, 3, WALL_Z - 0.25), 1)
	var far_a := Vector3(6, 0.9, WALL_Z + 0.6)   # 6 m from where the mine lands
	var far_b := Vector3(8, 0.9, WALL_Z + 1.0)   # 8 m from it, inside the chain's reach
	var away := Vector3(30, 0.9, 30)
	var a := _robot("A", far_a)
	var b := _robot("B", far_b)
	cam = Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 1.6, 0)
	var scene := (load(GUN) as PackedScene).instantiate()
	cam.add_child(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	w = scene as Weapon
	w.reserve = 0
	var d := w.data
	var cost := int(_num(w, "MINE_COST"))
	var probe_round := (d.projectile_scene as PackedScene).instantiate() as Projectile
	var trig := _num(probe_round, "MINE_TRIGGER")
	var life := _num(probe_round, "MINE_LIFE")
	var chain_dmg := probe_round.chain_damage
	probe_round.free()
	var mode_name: String = WeaponData.AltMode.keys()[int(d.alt_mode)]
	_check("the Tempest's alt mode is MINE", mode_name == "MINE", mode_name)
	_check("a mine costs 2 rounds, trips at 2.5 m and lasts 10 s", cost == 2 and int(w.alt_cost()) == 2 and is_equal_approx(trig, 2.5) and is_equal_approx(life, 10.0), "cost %d, alt_cost %d, %.1f m, %.1f s" % [cost, w.alt_cost(), trig, life])

	# A trigger round goes off on the wall.
	await _load(5)
	await _press("hip")
	await _wait(1.0)
	_check("a trigger round fired at the wall goes off on it", rounds.size() == 1 and _live() == null, "%d rounds, live %s" % [rounds.size(), _live() != null])

	# A mine sticks and waits.
	await _load(5)
	await _press("alt")
	await _wait(1.0)
	var m := _live()
	_check("a mine spends MINE_COST rounds on one orb", rounds.size() == 1 and w.mag == 3, "%d orbs, %d rounds left" % [rounds.size(), w.mag])
	_check("the mine is still there 1 s later", m != null)
	var p1 := m.global_position if m != null else Vector3.ZERO
	await _wait(1.0)
	m = _live()
	_check("and 2 s later, at rest on the wall", m != null and m.global_position.distance_to(p1) < 0.01 and absf(m.global_position.z - WALL_Z) < 0.5, "at %s" % (str(m.global_position.snapped(Vector3.ONE * 0.01)) if m != null else "gone"))
	_check("a robot 6 m away is unharmed", _sum("A") == 0.0 and _sum("B") == 0.0, "A %.0f, B %.0f" % [_sum("A"), _sum("B")])

	# A robot walks into it.
	var had := m != null # m is freed once it goes off, and a freed instance equals null
	var mine_at := m.global_position if m != null else Vector3(0, 1.6, WALL_Z)
	await _place(a, mine_at + Vector3(1.6, -0.6, 0.8))
	var t0 := clock
	while _live() != null and clock - t0 < 2.0:
		await get_tree().process_frame
	var took := clock - t0
	await _wait(0.2)
	_check("a robot within MINE_TRIGGER sets it off inside 0.4 s", had and _live() == null and took < 0.4, "%.2f s" % took)
	_check("that robot takes the blast", had and _sum("A") >= d.damage, "%.0f damage" % _sum("A"))
	_check("the chain reaches a second robot 8 m from the mine", had and is_equal_approx(_sum("B"), chain_dmg), "%.0f damage (chain %.0f)" % [_sum("B"), chain_dmg])

	# Left alone.
	await _place(a, away)
	await _place(b, away + Vector3(4, 0, 0))
	await _load(5)
	await _press("alt")
	await _wait(0.6) # it has landed
	var landed := _live() != null
	await _wait(maxf(0.0, life - 1.6))
	var before := _live() != null
	await _wait(1.8)
	_check("a mine left alone is still there 1 s before MINE_LIFE", landed and before, "landed %s, at %.1f s %s" % [landed, life - 1.0, before])
	_check("and gone after it", landed and _live() == null)

	# Straight into a robot.
	await _place(a, Vector3(0, 0.9, -8))
	await _load(5)
	await _press("alt")
	await _wait(0.6)
	_check("a mine round that strikes a robot goes off at once", rounds.size() == 1 and _live() == null and _sum("A") >= d.damage, "live %s, %.0f damage" % [_live() != null, _sum("A")])

	# Not enough rounds.
	await _place(a, away)
	await _load(1)
	await _press("alt")
	await _wait(0.4)
	_check("a tap on 1 round fires nothing", rounds.is_empty() and w.mag == 1, "%d orbs, %d left" % [rounds.size(), w.mag])

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
