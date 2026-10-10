extends Node
## Probe: the ATTENTION HEAD and the attention it puts on the player
## (enemy_attention.gd, scripts/systems/attention.gd).
## (1) it is wired: level builder, codex, one each on SUBURB, GROK and OVERSEER;
## (2) attention tightens every robot's aim: EnemyBase.scatter_aim's mean error
##     drops to ATTENDED_SPREAD of itself while the player is attended;
## (3) once it has the player, its gaze cone settles on them and the player is
##     attended; an idle robot within ALERT_RADIUS wakes onto the player, and an
##     engaged one that cannot see the player still gets their position;
## (4) the gaze lags: a sidestep out of the cone drops the attention, and the
##     cone finds the player again a moment later;
## (5) a wall between them blocks it; (6) its death ends the attention.
##   godot --headless --path . --audio-driver Dummy res://tests/attention_probe.tscn

const SCENE := "res://scenes/enemies/attention.tscn"
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
		if en.get("type", "") == "attention":
			n += 1
	return n

## Mean angle (degrees) scatter_aim puts on a straight-ahead shot.
func _mean_error(e: EnemyBase) -> float:
	var sum := 0.0
	for i in 400:
		sum += rad_to_deg(Vector3.FORWARD.angle_to(e.scatter_aim(Vector3.FORWARD, 8.0)))
	return sum / 400.0

## Waits up to `frames` physics frames for `cond` to hold; true if it did.
func _until(cond: Callable, frames: int) -> bool:
	for i in frames:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()

func _run() -> void:
	# 1. Wiring.
	_check("level builder knows attention", LevelBuilder.ENEMY_SCENES.get("attention", "") == SCENE)
	_check("codex entry", EnemyCodex.has("attention") and "attention" in EnemyCodex.ORDER)
	for lv in ["suburb", "grok", "overseer"]:
		_check("one on %s" % lv.to_upper(), _count(lv) == 1, str(_count(lv)))

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
	player.global_position = Vector3(0, 0, 14)

	# 2. Aim.
	var ally: EnemyBase = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	ally.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	ally.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(ally)
	ally.global_position = Vector3(-18, 0, 4)
	await _frames(2)
	Attention.until_ms = 0
	var loose := _mean_error(ally)
	Attention.until_ms = Time.get_ticks_msec() + 100000
	var tight := _mean_error(ally)
	Attention.until_ms = 0
	_check("attention tightens aim", loose > 1.0 and absf(tight / loose - Attention.ATTENDED_SPREAD) < 0.08,
			"%.2f -> %.2f deg" % [loose, tight])

	# 3. The gaze settles and the room wakes.
	var head: EnemyAttention = (load(SCENE) as PackedScene).instantiate()
	add_child(head)
	head.global_position = Vector3(0, 3.0, 0)
	head.set_physics_process(false) # posed: it watches, it does not fly
	head.target = player
	head.set_state(EnemyBase.State.ATTACK)
	await _frames(2)
	_check("not attended before it looks", not Attention.is_attended())
	var got := await _until(func() -> bool: head.gaze_tick(1.0 / 60.0); return Attention.is_attended(), 240)
	_check("its gaze settles on the player", got)
	_check("an idle robot nearby wakes onto the player", ally.state == EnemyBase.State.ALERT and ally.target == player,
			"state %d" % ally.state)
	# Engaged, blind: the head still feeds it the player's position.
	ally.set_state(EnemyBase.State.CHASE)
	ally._last_known_target_pos = Vector3(-50, 0, -50)
	player.global_position = Vector3(1.0, 0, 14)
	for i in 40:
		head.gaze_tick(1.0 / 60.0)
		await get_tree().physics_frame
	_check("an engaged robot is fed the player's position",
			ally._last_known_target_pos.distance_to(player.global_position) < 1.5,
			str(ally._last_known_target_pos))

	# 4. The gaze lags: sidestep out, then it finds you again.
	player.global_position = Vector3(9, 0, 14)
	for i in 3:
		head.gaze_tick(1.0 / 60.0)
		await get_tree().physics_frame
	var lost := await _until(func() -> bool: head.gaze_tick(1.0 / 60.0); return not Attention.is_attended(), 60)
	_check("a sidestep breaks the gaze", lost)
	got = await _until(func() -> bool: head.gaze_tick(1.0 / 60.0); return Attention.is_attended(), 240)
	_check("the cone finds the player again", got)

	# 5. A wall blocks it.
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wbs := BoxShape3D.new()
	wbs.size = Vector3(30, 8, 0.6)
	wcs.shape = wbs
	wall.add_child(wcs)
	add_child(wall)
	wall.global_position = Vector3(0, 3, 7)
	await _frames(2)
	head._los_t = 0.0 # re-check line of sight now, not at the next 10 Hz tick
	lost = await _until(func() -> bool: head.gaze_tick(1.0 / 60.0); return not Attention.is_attended(), 90)
	_check("a wall blocks the gaze", lost)
	wall.queue_free()
	await _frames(2)
	head._los_t = 0.0
	got = await _until(func() -> bool: head.gaze_tick(1.0 / 60.0); return Attention.is_attended(), 240)
	_check("back in the open, attended again", got)

	# 6. Death ends it.
	head.hp.apply_damage(99999.0, player)
	lost = await _until(func() -> bool: return not Attention.is_attended(), 60)
	_check("its death ends the attention", lost)
	_check("its cone goes dark", not head.cone_visible())

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
