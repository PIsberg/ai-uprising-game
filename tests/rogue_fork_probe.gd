extends Node3D
## ROGUE FORK: a skirmish event spawns a squad on a THIRD side that hunts the
## loyal robots and the player alike. On a baked navmesh with a held player and
## two loyal androids:
##   - _event_rogue_fork spawns ROGUE_SQUAD.size() forks: group "rogue", not
##     "hijacked", collision layer ROGUE_LAYER, kill label ROGUE ..., and
##     announces ROGUE FORK;
##   - forks 6 m from the player (14 m from the loyal androids) hurt the player
##     within 4 s, the damage sourced to a rogue;
##   - a loyal android takes a fork as its target within 3 s;
##   - the side rule: loyal fire on a fork lands, a fork's fire on a loyal robot
##     lands, a fork's fire on a fork is blocked, a hijacked robot's fire on a
##     fork lands;
##   - a lone fork 60 m from everything is still alive after 6 s (no burnout);
##   - a HIJACK charge turns a fork (rogue off, hijacked on);
##   - deleting the squad with the player as source pays ROGUE_BONUS each and
##     ROGUE_CONTAIN_BONUS on the last (rogue_deleted 4 times, the last with 0
##     left), while a fork a loyal robot deletes pays nothing;
##   - "rogue" is in EVENT_IDS and EVENT_TITLES and _run_event("rogue") spawns.
##   godot --headless --path . --audio-driver Dummy res://tests/rogue_fork_probe.tscn

const ANDROID := preload("res://scenes/enemies/android.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _fail: Array[String] = []
var _rogue_hits_on_player := 0.0
var _events: Array[String] = []
var _deleted: Array = [] ## [points, left] per rogue_deleted

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

func _taken(e: EnemyBase) -> float:
	return e.hp.max_health - e.hp.current_health if is_instance_valid(e) else INF

func _run() -> void:
	await _nav_floor(160.0)
	get_tree().current_scene = self if get_tree().current_scene == null else get_tree().current_scene
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0, 0)
	player.set_physics_process(false)
	var php := player.get_node("Damageable") as Damageable
	php.max_health = 100000.0
	php.current_health = 100000.0
	php.damaged.connect(func(a: float, s: Node) -> void:
		if is_instance_valid(s) and s.get("rogue") == true:
			_rogue_hits_on_player += a)
	GameState.set_state(GameState.State.PLAYING)
	GameState.current_level_path = "res://scenes/levels/level_gpt.tscn"
	GameState.skirmish_event.connect(func(title: String, _d: String) -> void: _events.append(title))
	GameState.rogue_deleted.connect(func(pts: int, left: int) -> void: _deleted.append([pts, left]))

	var loyal_a := _robot(Vector3(20, 0.1, 0))
	var loyal_b := _robot(Vector3(20, 0.1, 3))
	await _wait(0.2)
	loyal_b.set_physics_process(false)

	_check("rogue" in GameState.EVENT_IDS and GameState.EVENT_TITLES.has("rogue"), "the event is in the poll's list with a title")
	var before := get_tree().get_nodes_in_group("enemy").size()
	var squad: Array[EnemyBase] = GameState._event_rogue_fork(Vector3(6, 0, 0))
	await _wait(0.3)
	_check(squad.size() == GameState.ROGUE_SQUAD.size() and get_tree().get_nodes_in_group("enemy").size() == before + squad.size(),
			"the squad spawns", "%d forks" % squad.size())
	var all_rogue := true
	for e in squad:
		if not (e.rogue and e.is_in_group("rogue") and not e.hijacked and not e.is_in_group("hijacked")
				and e.collision_layer == EnemyBase.ROGUE_LAYER and e._kill_label().begins_with("ROGUE ")):
			all_rogue = false
	_check(all_rogue, "every fork is rogue: group, not hijacked, ROGUE_LAYER, ROGUE label")
	_check(_events.has("ROGUE FORK"), "the event is announced", str(_events))

	# They hunt the player (the nearest mark) and the loyal robots hunt them.
	var t := 0.0
	var loyal_targets_fork := false
	while t < 4.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if is_instance_valid(loyal_a.target) and loyal_a.target is Node and (loyal_a.target as Node).is_in_group("rogue"):
			loyal_targets_fork = true
	_check(_rogue_hits_on_player > 0.0, "forks hurt the player within 4 s", "%.0f" % _rogue_hits_on_player)
	_check(loyal_targets_fork, "a loyal android takes a fork as its target")

	# The side rule, applied directly.
	var fork := squad[0]
	var fork2 := squad[1]
	for e in squad:
		e.set_physics_process(false)
	loyal_a.set_physics_process(false)
	var h0 := fork.hp.current_health
	fork.hp.apply_damage(5.0, loyal_a)
	_check(fork.hp.current_health < h0, "loyal fire on a fork lands")
	h0 = loyal_b.hp.current_health
	loyal_b.hp.apply_damage(5.0, fork)
	_check(loyal_b.hp.current_health < h0, "a fork's fire on a loyal robot lands")
	h0 = fork2.hp.current_health
	fork2.hp.apply_damage(5.0, fork)
	_check(fork2.hp.current_health == h0, "a fork's fire on a fork is blocked")
	var turned := _robot(Vector3(-20, 0.1, -20))
	await _wait(0.2)
	turned.set_physics_process(false)
	_check(turned.hijack(30.0, player), "a hijack charge converts a loyal android")
	h0 = fork.hp.current_health
	fork.hp.apply_damage(5.0, turned)
	_check(fork.hp.current_health < h0, "a hijacked robot's fire on a fork lands")

	# No burnout, and a charge turns a fork.
	var lone := _robot(Vector3(60, 0.1, 60))
	await _wait(0.2)
	_check(lone.go_rogue(), "a lone android goes rogue")
	await _wait(6.0)
	_check(is_instance_valid(lone) and lone.hp.is_alive() and lone.rogue, "a lone fork is still alive and rogue after 6 s")
	_check(lone.hijack(5.0, player) and lone.hijacked and not lone.rogue and not lone.is_in_group("rogue")
			and lone.collision_layer == 2, "a HIJACK charge turns a fork to your side")

	# Deleting the squad.
	var score0 := GameState.score
	var paid_by_robot := _deleted.size()
	fork2.hp.apply_damage(99999.0, loyal_a)
	await _wait(0.1)
	_check(_deleted.size() == paid_by_robot, "a fork a loyal robot deletes pays nothing", str(_deleted))
	for e in squad:
		if is_instance_valid(e) and e.hp.is_alive():
			e.hp.apply_damage(99999.0, player)
			await _wait(0.1)
	var last: Array = _deleted[-1] if not _deleted.is_empty() else [0, -1]
	_check(_deleted.size() == squad.size() - 1 and int(last[1]) == 0 and int(last[0]) == GameState.ROGUE_BONUS + GameState.ROGUE_CONTAIN_BONUS,
			"your kills pay ROGUE_BONUS each and the last pays the containment bonus", str(_deleted))
	_check(GameState.score - score0 >= (squad.size() - 1) * GameState.ROGUE_BONUS + GameState.ROGUE_CONTAIN_BONUS,
			"the bonuses reach the score", "+%d" % (GameState.score - score0))

	# The director's dispatch.
	var n0 := get_tree().get_nodes_in_group("rogue").size()
	GameState._run_event("rogue")
	await _wait(0.3)
	_check(get_tree().get_nodes_in_group("rogue").size() >= n0 + 1, "_run_event(\"rogue\") spawns a squad")

	print("RESULT %s" % ("PASS" if _fail.is_empty() else "FAIL"))
	get_tree().quit(0 if _fail.is_empty() else 1)

## A baked navmesh floor, so the forks and the loyal robots path for real.
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
