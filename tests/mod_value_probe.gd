extends Node3D
## What each weapon mod is worth, measured in-engine per gun (#164: "is one an
## obvious pick?"). Every moddable gun fires for WINDOW seconds through its real
## trigger path at a frozen pack of three robots (HP topped up, so nothing dies)
## standing 3 m in front of a wall, and the probe tallies the damage actually dealt:
##   HIT  - aimed at the front robot: base, CHAIN ARC and THERMITE;
##   MISS - aimed at the wall between two robots: RICOCHET.
## Two packs: androids (armour 0) and gunners (armour 4, like most mid-game
## robots), because armour is paid per proc.
## Mod damage is told apart from the gun's own by GameState._secondary_hit, so an
## uplift is mod / direct damage inside ONE run (a shotgun's spread made separate
## runs differ by 10%+). RICOCHET is quoted against the base run's direct damage
## (what those shots would have dealt had they hit) and blended at BLEND_ACCURACY.
## The wall stands 15 m out, past the VK-7 Tesla's 13 m reach, so its RICOCHET reads 0.
## OVERRIDE is not a DPS
## mod (a turned robot burns out after 6 s); it is reported as the HP it skips.
##   godot --headless --path . --audio-driver Dummy res://tests/mod_value_probe.tscn

const WINDOW := 4.0
const DIST := 12.0
const BLEND_ACCURACY := 0.6 ## share of shots that land, for the blended column
const PACKS := {"android": "res://scenes/enemies/android.tscn", "gunner": "res://scenes/enemies/gunner.tscn"}

var _cam: Camera3D
var _shooter: Node3D
var _dealt := 0.0     ## the gun's own hits
var _mod_dealt := 0.0 ## arcs, burn ticks, bounces (GameState.apply_secondary_damage)

func _ready() -> void:
	_run.call_deferred()

func _robot(path: String, pos: Vector3) -> Node3D:
	var e: Node3D = (load(path) as PackedScene).instantiate()
	add_child(e)
	e.global_position = pos
	e.set_physics_process(false)
	e.set_process(false)
	var hp: Node = e.get_node_or_null("Damageable")
	hp.damaged.connect(_tally)
	return e

func _tally(amount: float, _src) -> void:
	if GameState._secondary_hit:
		_mod_dealt += amount
	else:
		_dealt += amount

func _topup(rs: Array) -> void:
	for r in rs:
		var hp: Node = (r as Node).get_node_or_null("Damageable")
		hp.max_health = 1000000.0
		hp.current_health = 1000000.0

## (direct, mod) damage per second one gun deals to the pack with `mod` fitted, aimed at `aim`.
func _measure(weapon_path: String, pack_path: String, mod: String, aim: Vector3) -> Vector2:
	var targets := [
		_robot(pack_path, Vector3(0, 0, -DIST)),
		_robot(pack_path, Vector3(2.5, 0, -DIST - 0.5)),
		_robot(pack_path, Vector3(-2.5, 0, -DIST + 0.5)),
	]
	for i in 3:
		await get_tree().physics_frame
	_cam.look_at(aim, Vector3.UP)
	var w: Weapon = (load(weapon_path) as PackedScene).instantiate()
	add_child(w)
	w.global_position = Vector3(0, 1.2, 0)
	w.mod_id = mod
	await get_tree().physics_frame
	_topup(targets)
	_dealt = 0.0
	_mod_dealt = 0.0
	var semi: bool = w.data.fire_mode == WeaponData.FireMode.SEMI or w.data.fire_mode == WeaponData.FireMode.BURST
	var t := 0.0
	var frame := 0
	while t < WINDOW:
		w.try_fire(true if not semi else (frame % 2 == 0), true, _cam, _shooter)
		await get_tree().physics_frame
		_topup(targets)
		t += get_physics_process_delta_time()
		frame += 1
	w.try_fire(false, false, _cam, _shooter)
	for i in 200: # burns finish ticking (3 s), arcs and bounces land
		await get_tree().physics_frame
		_topup(targets)
	var out := Vector2(_dealt, _mod_dealt) / WINDOW
	w.queue_free()
	for r in targets:
		(r as Node).queue_free()
	await get_tree().physics_frame
	return out

func _run() -> void:
	_shooter = Node3D.new()
	_shooter.add_to_group("player")
	add_child(_shooter)
	_cam = Camera3D.new()
	_cam.current = true
	add_child(_cam)
	_cam.global_position = Vector3(0, 1.2, 0)
	var floor_body := _box(Vector3(80, 1, 80), Vector3(0, -0.5, 0))
	var wall := _box(Vector3(30, 8, 1), Vector3(0, 4, -DIST - 3.5))
	add_child(floor_body)
	add_child(wall)
	await get_tree().physics_frame
	var guns: Array[String] = []
	for p in GameState.WEAPON_ORDER:
		if GameState.mod_compatible(p):
			guns.append(p)
	var hit_aim := Vector3(0, 0.9, -DIST)
	var miss_aim := Vector3(1.25, 0.9, -DIST - 3.0) # between the front robot and the right one
	for pack in PACKS:
		print("\n%s pack (armour %.0f)" % [pack, _stats(PACKS[pack]).x])
		print("%-10s %8s %7s %7s %9s %10s" % ["WEAPON", "baseDPS", "ARC%", "THERM%", "RICO/miss", "RICO@%d%%" % int(BLEND_ACCURACY * 100)])
		for g in guns:
			var wname := g.get_file().get_basename()
			var base: Vector2 = await _measure(g, PACKS[pack], "", hit_aim)
			var arc: Vector2 = await _measure(g, PACKS[pack], "arc", hit_aim)
			var therm: Vector2 = await _measure(g, PACKS[pack], "thermite", hit_aim)
			var rico: Vector2 = await _measure(g, PACKS[pack], "ricochet", miss_aim)
			var rico_per_miss: float = _share(rico.y, base.x)
			var blended: float = (1.0 - BLEND_ACCURACY) * rico_per_miss / BLEND_ACCURACY
			print("%-10s %8.0f %6.0f%% %6.0f%% %8.0f%% %9.0f%%" % [wname, base.x,
				_share(arc.y, arc.x) * 100.0, _share(therm.y, therm.x) * 100.0, rico_per_miss * 100.0, blended * 100.0])
	var hp := _stats(PACKS["gunner"]).y
	print("\nOVERRIDE: turns a robot at <=%.0f%% once per %.0f s: a %.0f HP gunner skips %.0f HP every %.0f s"
		% [WeaponMods.OVERRIDE_HP_FRACTION * 100.0, WeaponMods.OVERRIDE_COOLDOWN_MS / 1000.0, hp,
		hp * WeaponMods.OVERRIDE_HP_FRACTION, WeaponMods.OVERRIDE_COOLDOWN_MS / 1000.0])
	print("RESULT PASS (report)")
	get_tree().quit()

func _share(mod_dps: float, direct_dps: float) -> float:
	return mod_dps / direct_dps if direct_dps > 0.0 else 0.0

## (armour, max HP) as the subclass's _ready sets them.
func _stats(path: String) -> Vector2:
	var e := (load(path) as PackedScene).instantiate()
	add_child(e)
	var d := e.get_node("Damageable") as Damageable
	var out := Vector2(d.armor, d.max_health)
	e.free()
	return out

func _box(size: Vector3, pos: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	b.position = pos
	return b
