extends Node
## Probe: PROMPT INJECTION terminals (scripts/systems/prompt_injector.gd, def
## key `injectors`) and the jailbreak they broadcast (EnemyBase.jailbreak).
## (1) GEMINI, GROK, UPLINK and OVERSEER author one; built through the real
##     level scene it stands on clear floor, nothing solid inside its footprint;
## (2) standing at it for USE_TIME injects: every robot within RADIUS is
##     jailbroken (inert, no attacks) and one beyond it is not; a boss-sized
##     chassis only takes a short stun; the terminal is spent;
## (3) stepping off before USE_TIME injects nothing, and a spent terminal never
##     fires again;
## (4) a jailbroken robot comes back after JAILBREAK_TIME.
##   godot --headless --path . --audio-driver Dummy res://tests/injector_probe.tscn

const LEVELS := ["gemini", "grok", "uplink", "overseer"]
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

func _run() -> void:
	# 1. Authored, and standing on clear floor in the real level.
	for id in LEVELS:
		var n: int = LevelDefs.get_def(id).get("injectors", []).size()
		_check("%s authors an injector" % id, n >= 1, str(n))
		var lvl: Node = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
		add_child(lvl)
		await _frames(3)
		var built := get_tree().get_nodes_in_group("injector")
		_check("%s builds it" % id, built.size() == n, "%d of %d" % [built.size(), n])
		var space := (lvl as Node3D).get_world_3d().direct_space_state
		for inj in built:
			var p := (inj as Node3D).global_position
			var down := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 0.6, 1)
			_check("%s injector at %s is on the floor" % [id, p], not space.intersect_ray(down).is_empty())
			var box := BoxShape3D.new()
			box.size = Vector3(0.9, 1.4, 0.9)
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = box
			q.collision_mask = 1
			q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.85)
			var hits := space.intersect_shape(q, 4)
			_check("%s injector at %s has clear room" % [id, p], hits.is_empty(),
					str(hits.map(func(h: Dictionary) -> String: return str(h.collider.name))))
		lvl.queue_free()
		await _frames(3)

	# 2-4. Mechanics in an empty room.
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(200, 1, 200)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	player.collision_mask = 1
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	pcs.shape = cap
	pcs.position.y = 0.9
	player.add_child(pcs)
	add_child(player)
	player.global_position = Vector3(0, 0, 40)

	var inj := PromptInjector.new()
	add_child(inj)
	inj.global_position = Vector3.ZERO
	var near: Array[EnemyBase] = []
	for x in [-8.0, 8.0, 15.0]:
		near.append(_robot(Vector3(x, 0, -6)))
	var far := _robot(Vector3(0, 0, -(PromptInjector.RADIUS + 8.0)))
	var boss := _robot(Vector3(0, 0, -10))
	boss.max_health = 900.0 # set-piece sized: resists like a hijack
	await _frames(3)

	# 3a. Step off before it finishes typing.
	player.global_position = Vector3(0.3, 0, 0.3)
	await _frames(int(PromptInjector.USE_TIME * 60.0 * 0.5))
	player.global_position = Vector3(0, 0, 40)
	await _frames(int(PromptInjector.USE_TIME * 60.0) + 10)
	_check("stepping off early injects nothing", not inj.used and not near[0].is_jailbroken())

	# 2. Stand there for the whole time.
	player.global_position = Vector3(0.3, 0, 0.3)
	var fired := false
	for i in int(PromptInjector.USE_TIME * 60.0 * 2.5):
		await get_tree().physics_frame
		if inj.used:
			fired = true
			break
	_check("standing at it injects", fired)
	var all_near := true
	for e in near:
		all_near = all_near and e.is_jailbroken() and e._emp_t > 0.0
	_check("robots within RADIUS are jailbroken and inert", all_near)
	_check("a robot beyond RADIUS is not", not far.is_jailbroken())
	_check("a boss-sized chassis is only stunned", not boss.is_jailbroken() and boss._emp_t > 0.0
			and boss._emp_t <= PromptInjector.BOSS_STUN + 0.05, "emp %.2f" % boss._emp_t)

	# 3b. Spent.
	player.global_position = Vector3(0, 0, 40)
	await _frames(5)
	for e in near:
		e._emp_t = 0.0
		e._jailbreak_t = 0.0
	player.global_position = Vector3(0.3, 0, 0.3)
	await _frames(int(PromptInjector.USE_TIME * 60.0 * 2.0))
	_check("a spent terminal never fires again", not near[0].is_jailbroken())

	# 4. They come back (the wear-off runs in its physics tick: wake it).
	near[1].process_mode = Node.PROCESS_MODE_INHERIT
	near[1].jailbreak(0.5)
	_check("jailbreak takes", near[1].is_jailbroken())
	await _frames(45)
	_check("and wears off", not near[1].is_jailbroken() and near[1]._emp_t <= 0.0)

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _robot(pos: Vector3) -> EnemyBase:
	var e: EnemyBase = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	# AI off so nobody walks across RADIUS mid-test; collision kept.
	e.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	e.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(e)
	e.global_position = pos
	return e
