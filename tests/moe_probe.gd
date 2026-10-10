extends Node
## Probe: the MIXTURE OF EXPERTS (enemy_moe.gd).
## (1) it is wired: level builder, codex, one on NEON and one on CRUCIBLE;
## (2) four expert pods orbit it, each a separate target on the enemy layer
##     with its own Damageable;
## (3) routing to an expert switches how it fights: SNIPER one heavy tight
##     shot, SCATTER a wide burst, SPRINT a faster chassis, SHIELD takes
##     SHIELD_MULT of a hit; the hologram names the active expert;
## (4) a rifle hit on a pod hurts the pod, not the body; a dead pod's expert
##     is never routed to again;
## (5) all pods down: the router collapses, the body takes COLLAPSE_MULT and
##     the hologram says so;
## (6) killing the body takes its remaining pods with it.
##   godot --headless --path . --audio-driver Dummy res://tests/moe_probe.tscn

const SCENE := "res://scenes/enemies/moe.tscn"
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _count(level: String) -> int:
	var n := 0
	for en in LevelDefs.get_def(level).get("enemies", []):
		if en.get("type", "") == "moe":
			n += 1
	return n

func _run() -> void:
	# 1. Wiring.
	_check("level builder knows moe", LevelBuilder.ENEMY_SCENES.get("moe", "") == SCENE)
	_check("codex entry", EnemyCodex.has("moe") and "moe" in EnemyCodex.ORDER)
	_check("one on NEON", _count("neon") == 1, str(_count("neon")))
	_check("one on CRUCIBLE", _count("crucible") == 1, str(_count("crucible")))

	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(200, 1, 200)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	var shooter := Node3D.new()
	shooter.add_to_group("player")
	add_child(shooter)
	shooter.global_position = Vector3(0, 1.5, 40)

	var e: EnemyMoE = (load(SCENE) as PackedScene).instantiate()
	add_child(e)
	# Posed: AI off and the orbit still. (PROCESS_MODE_DISABLED would also pull
	# the pods, which keep the default disable mode, out of physics.)
	e.set_physics_process(false)
	e.set_process(false)
	e.global_position = Vector3.ZERO
	await _frames(3)

	# 2. Pods.
	var pods := e.pods()
	_check("four expert pods", pods.size() == EnemyMoE.EXPERTS.size(), str(pods.size()))
	var pods_ok := true
	for p in pods:
		pods_ok = pods_ok and p is CollisionObject3D and (p as CollisionObject3D).collision_layer & 4 \
				and p.get_node_or_null("Damageable") is Damageable
	_check("each pod is its own target on the enemy layer", pods_ok)

	# 3. Experts change the fight.
	e.route_to(EnemyMoE.SNIPER)
	_check("SNIPER: one heavy, tight shot", e.burst_count == 1 and e.hitscan_damage >= 18.0
			and e.burst_spread_deg <= 1.0, "%d x %.0f" % [e.burst_count, e.hitscan_damage])
	_check("hologram names the expert", "SNIPER" in e.status_text(), e.status_text())
	e.route_to(EnemyMoE.SCATTER)
	_check("SCATTER: a wide burst", e.burst_count >= 5 and e.burst_spread_deg >= 6.0)
	e.route_to(EnemyMoE.SPRINT)
	var sprint_speed := e.move_speed
	e.route_to(EnemyMoE.SCATTER)
	_check("SPRINT: a faster chassis", sprint_speed > e.move_speed * 1.4, "%.1f vs %.1f" % [sprint_speed, e.move_speed])
	e.route_to(EnemyMoE.SHIELD)
	_check("SHIELD: takes SHIELD_MULT", is_equal_approx(e.modify_incoming_damage(100.0, shooter), 100.0 * EnemyMoE.SHIELD_MULT))
	e.route_to(EnemyMoE.SNIPER)
	_check("unshielded: full damage", is_equal_approx(e.modify_incoming_damage(100.0, shooter), 100.0))

	# 4. Shoot a pod.
	var rifle: Weapon = (load("res://scenes/weapons/rifle.tscn") as PackedScene).instantiate()
	add_child(rifle)
	rifle._active_shooter = shooter
	var pod: Node3D = pods[EnemyMoE.SHIELD]
	var pod_hp: Damageable = pod.get_node("Damageable")
	var body_hp := e.hp.current_health
	var pod_before := pod_hp.current_health
	var at := pod.global_position
	rifle._do_hitscan(at + Vector3(0, 0, 8), Vector3(0, 0, -1))
	_check("a rifle hit on a pod hurts the pod", pod_hp.current_health < pod_before,
			"%.0f -> %.0f" % [pod_before, pod_hp.current_health])
	_check("... and not the body", is_equal_approx(e.hp.current_health, body_hp))
	pod_hp.apply_damage(99999.0, shooter)
	await _frames(2)
	var shield_seen := false
	for i in 40:
		e.route_now()
		shield_seen = shield_seen or e.active == EnemyMoE.SHIELD
	_check("a dead pod's expert is never routed to", not shield_seen and not e.is_alive_expert(EnemyMoE.SHIELD))

	# 5. Collapse.
	for k in EnemyMoE.EXPERTS.size():
		var pd: Node = e.pods()[k] if k < e.pods().size() else null
		if is_instance_valid(pd):
			(pd.get_node("Damageable") as Damageable).apply_damage(99999.0, shooter)
	await _frames(2)
	_check("all pods down: router collapsed", e.collapsed and "COLLAPSED" in e.status_text(), e.status_text())
	_check("collapsed: takes COLLAPSE_MULT", is_equal_approx(e.modify_incoming_damage(100.0, shooter),
			100.0 * EnemyMoE.COLLAPSE_MULT))

	# 6. Death takes the pods.
	var e2: EnemyMoE = (load(SCENE) as PackedScene).instantiate()
	e2.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	e2.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(e2)
	e2.global_position = Vector3(20, 0, 0)
	await _frames(3)
	var left := e2.pods()
	e2.process_mode = Node.PROCESS_MODE_INHERIT
	e2.hp.apply_damage(99999.0, shooter)
	await _frames(3)
	var gone := true
	for p in left:
		gone = gone and (not is_instance_valid(p) or (p as Node).is_queued_for_deletion())
	_check("its death takes the pods", gone)

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
