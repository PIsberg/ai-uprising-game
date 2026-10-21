extends Node3D
## HIJACK overload: in its last EnemyBase.OVERLOAD_WARN seconds a hijacked robot
## stops fighting and runs at the densest knot of hostile robots, then its
## burnout detonates. On a baked navmesh, with a squad of three androids packed
## 11 m from the converted unit, one android off on its own 18 m away and a
## boss-sized android inside the knot:
##   - before the warning it fights (it is not yet running for the knot);
##   - in the warning it closes on the knot (distance drops by at least 3 m) and
##     reads as overloading (is_overloading);
##   - at burnout it dies, and every robot within OVERLOAD_RADIUS of the blast
##     takes damage, the squad member at its centre at least 80;
##   - the lone android far off is untouched;
##   - the boss-sized robot takes at most half what a plain one at its distance would;
##   - the player, standing 3 m from the knot, takes nothing from the blast;
##   - the first overload teaches the rule once (MECHANIC_HINTS.hijack_overload);
##   - a hijack shorter than OVERLOAD_MIN_LIFE never overloads;
##   - an escort (aligned for good) never overloads.
##   godot --headless --path . --audio-driver Dummy res://tests/hijack_overload_probe.tscn

const ANDROID := preload("res://scenes/enemies/android.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _fail: Array[String] = []
var _blast_on_player := 0.0
var _bomb: EnemyBase = null
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

func _robot(pos: Vector3) -> EnemyBase:
	var e: EnemyBase = ANDROID.instantiate()
	add_child(e)
	e.global_position = pos
	return e

var _before: Dictionary = {}

## Blast damage: health lost since the snapshot taken just before burnout.
func _taken(e: EnemyBase) -> float:
	return float(_before.get(e, e.hp.max_health)) - e.hp.current_health if is_instance_valid(e) else INF

func _run() -> void:
	await _nav_floor(120.0)
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = Vector3(14, 0, 3)
	player.set_physics_process(false)
	var php := player.get_node("Damageable") as Damageable
	php.max_health = 100000.0
	php.current_health = 100000.0
	php.damaged.connect(func(a: float, s: Node) -> void:
			if s == _bomb or s == player:
				_blast_on_player += a)
	_bomb = _robot(Vector3(0, 0.1, 0))
	var knot: Array[EnemyBase] = [_robot(Vector3(11, 0.1, 0)), _robot(Vector3(12.2, 0.1, 0.8)), _robot(Vector3(12.2, 0.1, -0.8))]
	var boss := _robot(Vector3(13.2, 0.1, 0))
	var lone := _robot(Vector3(0, 0.1, -18))
	await _wait(0.2)
	boss.hp.max_health = 900.0
	boss.hp.current_health = 900.0
	boss.max_health = 900.0
	for e: EnemyBase in knot + [boss, lone]:
		e.set_physics_process(false) # hold the scene still: only the bomb moves
	GameState._taught.erase("hijack_overload")
	GameState.teach_hint.connect(func(t: String) -> void: _hints.append(t))
	var life := 5.0
	_check(_bomb.hijack(life, player), "the android converts")
	await _wait(life - EnemyBase.OVERLOAD_WARN - 0.4)
	var d_before := _bomb.global_position.distance_to(knot[0].global_position)
	_check(not _bomb.is_overloading(), "before the warning it is not overloading")
	await _wait(0.6)
	_check(_bomb.is_overloading(), "in the warning it reads as overloading")
	_check(_hints.any(func(h: String) -> bool: return h == GameState.MECHANIC_HINTS["hijack_overload"]),
			"the first overload teaches the rule", str(_hints))
	await _wait(EnemyBase.OVERLOAD_WARN - 0.5)
	var d_late := _bomb.global_position.distance_to(knot[0].global_position) if is_instance_valid(_bomb) else 0.0
	_check(d_before - d_late >= 3.0, "it runs at the knot", "%.1f m -> %.1f m" % [d_before, d_late])
	# Where it actually goes off: it keeps running until the clock hits 0.
	var at := [_bomb.global_position]
	_bomb.hp.died.connect(func(_s: Node) -> void:
			if is_instance_valid(_bomb):
				at[0] = _bomb.global_position)
	# Health just before the blast: the overload does not zap, so what goes
	# missing from here on is the blast (the zaps before it are not counted).
	_before.clear()
	for e: EnemyBase in knot + [boss, lone]:
		_before[e] = e.hp.current_health
	await _wait(0.6)
	_check(not is_instance_valid(_bomb) or not _bomb.hp.is_alive(), "it dies at burnout")
	var blast_at: Vector3 = at[0]
	var hit_all := true
	var centre := 0.0
	for e in knot:
		var dist := e.global_position.distance_to(blast_at) if is_instance_valid(e) else 0.0
		var t := _taken(e)
		if dist <= EnemyBase.OVERLOAD_RADIUS and t <= 0.0:
			hit_all = false
		centre = maxf(centre, t)
	_check(hit_all, "every knot robot in range takes the blast")
	_check(centre >= 80.0, "the robot nearest the blast takes at least 80", "%.0f" % centre)
	_check(_taken(lone) == 0.0, "the lone android far off is untouched", "%.0f" % _taken(lone))
	var bd := boss.global_position.distance_to(blast_at)
	var plain := EnemyBase.overload_blast_damage(bd)
	_check(_taken(boss) > 0.0 and _taken(boss) <= plain * 0.5 + 0.5, "a boss-sized robot takes at most half",
			"took %.0f, a plain robot there %.0f" % [_taken(boss), plain])
	_check(_blast_on_player == 0.0, "the player beside the knot takes nothing from it", "%.0f" % _blast_on_player)

	# A short hijack fights to the end and burns out without a blast.
	var shorty := _robot(Vector3(30, 0.1, 30))
	var near := _robot(Vector3(32, 0.1, 30))
	await _wait(0.2)
	near.set_physics_process(false)
	shorty.hijack(EnemyBase.OVERLOAD_MIN_LIFE - 1.0, player)
	var never := true
	var t := 0.0
	while t < EnemyBase.OVERLOAD_MIN_LIFE - 0.9:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if is_instance_valid(shorty) and shorty.is_overloading():
			never = false
	_check(never, "a hijack shorter than OVERLOAD_MIN_LIFE never overloads")
	# An escort is aligned for good: no clock, no overload.
	var esc := _robot(Vector3(-20, 0.1, 10))
	await _wait(0.2)
	esc.hijack(1.0, player)
	esc.escort_goal = Vector3(-20, 0, 30)
	await _wait(1.6)
	_check(is_instance_valid(esc) and esc.hp.is_alive() and not esc.is_overloading(), "an escort never overloads")

	print("RESULT %s" % ("PASS" if _fail.is_empty() else "FAIL"))
	get_tree().quit(0 if _fail.is_empty() else 1)

## A baked navmesh floor, so the overloading robot paths for real.
func _nav_floor(size: float) -> void:
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	fmi.mesh = pm
	nav.add_child(fmi)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size, 1, size)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	sb.add_child(cs)
	nav.add_child(sb)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nm.agent_radius = 0.5
	nm.cell_size = 0.25
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh(false)
	for i in 3:
		await get_tree().physics_frame
