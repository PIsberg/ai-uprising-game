extends Node
## Probe: the CX-4 CASCADE, the early horde-clearer. Its rounds PRIME the robot
## they hit; a primed robot that dies (to anything) inside Cascade.PRIME_TIME
## detonates, and every hostile the blast kills detonates in turn, so one kill in a
## packed horde pops the whole pack.
## (1) data: the gun exists, carries cascade damage/radius, sits between the
##     Breacher and the Maelstrom in WEAPON_ORDER and is in the warp arsenal;
## (2) one cascade kill in a ring of six robots chains through all of them, a
##     robot outside the radius is untouched, the player inside it is untouched,
##     and GameState reports one chain of six;
## (3) the same kill from the rifle detonates nothing;
## (4) a primed robot finished by an untagged hit (a grenade) still detonates,
##     but once the prime has expired it does not;
## (5) the chain is bounded: each generation's blast is weaker, so a long line
##     of robots does not all pop off one kill;
## (6) bosses are never primed;
## (7) a cascade blast sets off an explosive barrel in range, leaves a plain
##     crate standing, and leaves a barrel out of range alone.
##   godot --headless --path . --audio-driver Dummy res://tests/cascade_probe.tscn

const ANDROID := "res://scenes/enemies/android.tscn"
const CASCADE := "res://scenes/weapons/cascade.tscn"
var ok := true
var _chains: Array = []

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	# 1. Data.
	var exists := ResourceLoader.exists(CASCADE)
	_check("cascade scene exists", exists)
	if not exists:
		_finish()
		return
	var d: WeaponData = load("res://assets/weapons/cascade_data.tres")
	_check("cascade carries blast damage", d.cascade_damage > 0.0, "%.0f" % d.cascade_damage)
	_check("cascade carries blast radius", d.cascade_radius > 0.0, "%.1f m" % d.cascade_radius)
	var order: Array = GameState.WEAPON_ORDER
	var ci := order.find(CASCADE)
	_check("ranked after the Breacher", ci > order.find("res://scenes/weapons/shotgun.tscn"), "rank %d" % ci)
	_check("ranked before the Maelstrom", ci >= 0 and ci < order.find("res://scenes/weapons/magnum.tscn"))
	_check("in the warp arsenal", GameState.ALL_WEAPONS.has(CASCADE))
	_check("rifle has no cascade", (load("res://assets/weapons/rifle_data.tres") as WeaponData).cascade_damage == 0.0)
	if GameState.has_signal("cascade_chain"):
		GameState.cascade_chain.connect(func(n: int, _pos: Vector3) -> void: _chains.append(n))
	else:
		_check("GameState has cascade_chain", false)

	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(400, 1, 400)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	var shooter := Node3D.new()
	shooter.add_to_group("player")
	add_child(shooter)
	shooter.global_position = Vector3(0, 1.5, 80)
	# A stand-in player body inside the blast: the cascade must never hurt it.
	var me := Node3D.new()
	me.add_to_group("player")
	var me_hp := Damageable.new()
	me_hp.name = "Damageable"
	me_hp.max_health = 100.0
	me.add_child(me_hp)
	add_child(me)
	me.global_position = Vector3(1.5, 0, 0)
	me_hp.current_health = 100.0

	var gun: Weapon = (load(CASCADE) as PackedScene).instantiate()
	add_child(gun)
	gun._active_shooter = shooter
	var blast: float = d.cascade_damage

	# 2. A ring of six, one kill.
	var ring := _ring(Vector3.ZERO, 6, d.cascade_radius * 0.45)
	var far := _robot(Vector3(d.cascade_radius * 2.5, 0, 0))
	await _frames(3)
	_hp_all(ring, blast * 0.6)
	_set_hp(far, 10000.0)
	ring[0].hp.current_health = 1.0
	_chains.clear()
	gun._do_hitscan(ring[0].global_position + Vector3(0, 1.2, 10), Vector3(0, 0, -1))
	_check("cascade round killed the first robot", not ring[0].hp.is_alive())
	await _settle()
	var dead := ring.filter(func(e) -> bool: return not is_instance_valid(e) or not e.hp.is_alive()).size()
	_check("the whole ring chained", dead == ring.size(), "%d / %d" % [dead, ring.size()])
	_check("robot outside the radius untouched", far.hp.current_health == 10000.0, "%.0f" % far.hp.current_health)
	_check("player inside the blast untouched", me_hp.current_health == 100.0, "%.0f" % me_hp.current_health)
	_check("one chain of six reported", _chains == [6], str(_chains))
	_clear()

	# 3. The rifle detonates nothing.
	var rifle: Weapon = (load("res://scenes/weapons/rifle.tscn") as PackedScene).instantiate()
	add_child(rifle)
	rifle._active_shooter = shooter
	var ring2 := _ring(Vector3(60, 0, 0), 6, d.cascade_radius * 0.45)
	await _frames(3)
	_hp_all(ring2, blast * 0.6)
	ring2[0].hp.current_health = 1.0
	_chains.clear()
	rifle._do_hitscan(ring2[0].global_position + Vector3(0, 1.2, 10), Vector3(0, 0, -1))
	_check("rifle killed the first robot", not ring2[0].hp.is_alive())
	await _settle()
	var hurt := 0
	for i in range(1, ring2.size()):
		if ring2[i].hp.current_health < ring2[i].hp.max_health:
			hurt += 1
	_check("rifle kill: neighbours untouched", hurt == 0, "%d hurt" % hurt)
	_check("rifle kill: no chain", _chains.is_empty(), str(_chains))
	_clear()

	# 4. Primed, then finished by a grenade; and an expired prime.
	var ring3 := _ring(Vector3(-60, 0, 0), 4, d.cascade_radius * 0.45)
	await _frames(3)
	_hp_all(ring3, blast * 0.6)
	_set_hp(ring3[0], 400.0) # tough, but under Cascade.BOSS_HP
	gun._do_hitscan(ring3[0].global_position + Vector3(0, 1.2, 10), Vector3(0, 0, -1))
	_check("cascade hit primed the robot", Cascade.is_primed(ring3[0]))
	_chains.clear()
	ring3[0].hp.apply_damage(999999.0, shooter, false, ring3[0].global_position)
	await _settle()
	var dead3 := ring3.filter(func(e) -> bool: return not is_instance_valid(e) or not e.hp.is_alive()).size()
	_check("primed robot killed by a grenade still detonates", dead3 == ring3.size(), "%d / %d" % [dead3, ring3.size()])
	_clear()
	var ring4 := _ring(Vector3(0, 0, -60), 4, d.cascade_radius * 0.45)
	await _frames(3)
	_hp_all(ring4, blast * 0.6)
	_set_hp(ring4[0], 400.0)
	gun._do_hitscan(ring4[0].global_position + Vector3(0, 1.2, 10), Vector3(0, 0, -1))
	for i in int((Cascade.PRIME_TIME + 0.3) / 0.25):
		await get_tree().create_timer(0.25).timeout
	_check("prime expires", not Cascade.is_primed(ring4[0]) and ring4[0].has_node("CascadeCharge"))
	_chains.clear()
	ring4[0].hp.apply_damage(999999.0, shooter, false, ring4[0].global_position)
	await _settle()
	var hurt4 := 0
	for i in range(1, ring4.size()):
		if ring4[i].hp.current_health < ring4[i].hp.max_health:
			hurt4 += 1
	_check("expired prime: no blast", hurt4 == 0 and _chains.is_empty(), "%d hurt, %s" % [hurt4, str(_chains)])
	_clear()

	# 5. A long line: robots one blast-radius-and-a-bit apart along x, each with
	# just under a full blast of health, so only decay can stop the chain.
	var line: Array = []
	for i in 30:
		line.append(_robot(Vector3(-100 + i * d.cascade_radius * 0.8, 0, 60)))
	await _frames(3)
	_hp_all(line, blast * 0.95)
	line[0].hp.current_health = 1.0
	_chains.clear()
	gun._do_hitscan(line[0].global_position + Vector3(0, 1.2, 10), Vector3(0, 0, -1))
	for i in 3:
		await _settle()
	var popped := line.filter(func(e) -> bool: return not is_instance_valid(e) or not e.hp.is_alive()).size()
	_check("the chain ran some way", popped >= 2, "%d popped" % popped)
	_check("the chain is bounded", popped < line.size(), "%d of %d popped" % [popped, line.size()])
	_clear()

	# 6. Bosses are never primed.
	var boss := _robot(Vector3(0, 0, 120))
	await _frames(3)
	_set_hp(boss, 5000.0)
	gun._do_hitscan(boss.global_position + Vector3(0, 1.2, 10), Vector3(0, 0, -1))
	_check("boss-sized robot not primed", not Cascade.is_primed(boss))

	# 7. Props: the blast sets off explosive ones in range only.
	var c7 := Vector3(-120, 0, -120)
	var lone := _robot(c7)
	var barrel := _prop("res://scenes/props/barrel.tscn", c7 + Vector3(d.cascade_radius * 0.6, 0, 0))
	var crate := _prop("res://scenes/props/crate.tscn", c7 + Vector3(-d.cascade_radius * 0.6, 0, 0)) # in the cascade, out of the line of fire and the barrel's splash
	var far_barrel := _prop("res://scenes/props/barrel.tscn", c7 + Vector3(-d.cascade_radius * 2.5, 0, 0))
	await _frames(3)
	var crate_hp: float = crate.hp.current_health
	lone.hp.current_health = 1.0
	gun._do_hitscan(lone.global_position + Vector3(0, 1.2, 10), Vector3(0, 0, -1))
	await _settle()
	_check("cascade sets off a barrel in range", not is_instance_valid(barrel))
	_check("a plain crate is left alone", is_instance_valid(crate) and crate.hp.current_health == crate_hp, "valid=%s hp %.0f -> %.0f" % [is_instance_valid(crate), crate_hp, crate.hp.current_health if is_instance_valid(crate) else -1.0])
	_check("a barrel out of range is left alone", is_instance_valid(far_barrel))
	_finish()

func _prop(scene: String, pos: Vector3) -> Node3D:
	var p: Node3D = (load(scene) as PackedScene).instantiate()
	add_child(p)
	p.global_position = pos
	return p

func _finish() -> void:
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

## Wait for a chain to finish: pops land a beat apart, so give it a second and a half.
func _settle() -> void:
	for i in 6:
		await get_tree().create_timer(0.25).timeout

## A ring of `n` robots. Health is set by _hp_all AFTER a few frames:
## EnemyBase._sync_stats runs deferred and re-applies the authored max_health.
func _ring(center: Vector3, n: int, r: float) -> Array:
	var out: Array = []
	for i in n:
		var a := TAU * i / n
		out.append(_robot(center + Vector3(cos(a), 0, sin(a)) * r))
	return out

func _hp_all(robots: Array, health: float) -> void:
	for e in robots:
		_set_hp(e, health)

func _set_hp(e: EnemyBase, health: float) -> void:
	e.hp.max_health = health
	e.hp.current_health = health

func _clear() -> void:
	for c in get_children():
		if c is EnemyBase:
			c.queue_free()

func _robot(pos: Vector3, scene: String = ANDROID) -> EnemyBase:
	var e: EnemyBase = (load(scene) as PackedScene).instantiate()
	# AI off, collision on: a disabled body is otherwise REMOVED from physics.
	e.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	e.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(e)
	e.global_position = pos
	# The death tweens are bound to the robot, so it must process when it dies;
	# its AI stays asleep (physics off).
	e.process_mode = Node.PROCESS_MODE_INHERIT
	e.set_physics_process(false)
	return e
