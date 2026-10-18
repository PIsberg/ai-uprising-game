extends Node
## Dev probe: the ADVERSARIAL PATCH (AdversarialPatch, scripts/systems/adversarial_patch.gd).
## Wearing it, robot optics read the player as a household object; each robot
## with eyes on them builds confidence (faster up close) until it sees a human.
## (1) without the patch a robot facing the player at 20 m sees them;
## (2) the patch action spends a charge and goes active;
## (3) with it, a robot facing the player at 20 m does not see them after 2 s,
##     carries a partial confidence and a decoy tag ("... NN%");
## (4) a robot 3 m away sees through it inside 3 s and its tag reads HUMAN;
## (5) firing breaks the patch;
## (6) a robot already hunting the player starts at the head-start confidence;
## (7) the clock runs out; with no charges left the action does nothing;
## (8) melee while patched TAGS a robot: it moves to the player layer and the
##     squad's fire damages it (red-checked: without the Damageable exception it took 0);
## (9) a vision scanner ignores a patched player beyond SCANNER_RANGE.
##   godot --headless --path . --audio-driver Dummy res://tests/adversarial_patch_probe.tscn

const ENEMY := "res://scenes/enemies/android.tscn"

var _fails := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _tap(action: String) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(1)

## Robot at `pos` turned to face `at`, frozen in place so only its eyes work.
func _sentry(pos: Vector3, at: Vector3) -> EnemyBase:
	var e: EnemyBase = load(ENEMY).instantiate()
	get_tree().root.add_child(e)
	e.global_position = pos
	var d := at - pos
	e.rotation.y = atan2(-d.x, -d.z)
	e.move_speed = 0.0
	e.sight_range = 40.0
	return e

func _seen(e: EnemyBase, t: Node3D) -> bool:
	return e._compute_can_see(t)

func _run() -> void:
	var script: Script = load("res://scripts/systems/adversarial_patch.gd")
	_check(script != null, "AdversarialPatch script exists")
	if script == null:
		print("RESULT FAIL")
		get_tree().quit(1)
		return
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	get_tree().root.add_child(floor_body)
	var player: Node3D = load("res://scenes/player/player.tscn").instantiate()
	get_tree().root.add_child(player)
	player.get("hp").invulnerable = true
	var patch: Node = player.get_node_or_null("AdversarialPatch")
	_check(patch != null, "player carries an AdversarialPatch")
	if patch == null:
		print("RESULT FAIL")
		get_tree().quit(1)
		return
	await _frames(4)

	# 1. Baseline.
	var far := _sentry(Vector3(0, 0, -20), Vector3.ZERO)
	await _frames(4)
	_check(_seen(far, player), "unpatched player at 20 m is seen")

	# 2. Wear it.
	var charges0: int = patch.charges
	await _tap("adversarial_patch")
	_check(patch.active and patch.charges == charges0 - 1, "action spends a charge and activates (charges %d -> %d)" % [charges0, patch.charges])

	# 3. Far robot is fooled for a while.
	far.patch_confidence = 0.0
	for i in 8: # 2 s in short waits: one long timer stalls autoload ticking headless
		await get_tree().create_timer(0.25, true, true).timeout
	var far_seen := _seen(far, player)
	print("far: confidence %.2f tag '%s' seen=%s" % [far.patch_confidence, patch.tag_text(far), far_seen])
	_check(not far_seen, "patched player at 20 m not seen after 2 s")
	_check(far.patch_confidence > 0.0 and far.patch_confidence < 1.0, "far robot carries partial confidence")
	_check(patch.tag_text(far).ends_with("%") and not patch.tag_text(far).begins_with("HUMAN"), "far tag names a decoy class")

	# 4. Close robot sees through.
	var near := _sentry(Vector3(3, 0, 0), Vector3.ZERO)
	var t0 := Time.get_ticks_msec()
	var through := false
	for i in 12:
		await get_tree().create_timer(0.25, true, true).timeout
		if _seen(near, player):
			through = true
			break
	print("near: saw through after %.2f s, confidence %.2f, tag '%s'" % [(Time.get_ticks_msec() - t0) / 1000.0, near.patch_confidence, patch.tag_text(near)])
	_check(through, "robot at 3 m sees through within 3 s")
	_check(patch.tag_text(near).begins_with("HUMAN"), "seen-through tag reads HUMAN")
	near.queue_free()

	# 5. Firing breaks it.
	GameState.register_shot()
	await _frames(2)
	_check(not patch.active, "a shot breaks the patch")
	_check(_seen(far, player), "far robot sees the player again once the patch is off")

	# 6. Head start for a robot already hunting.
	far.set_state(EnemyBase.State.CHASE)
	far.target = player
	await _tap("adversarial_patch")
	_check(patch.active, "second charge activates")
	_check(far.patch_confidence >= patch.HUNT_HEAD_START - 0.01, "hunting robot starts at the head start (%.2f)" % far.patch_confidence)

	# 7. Clock, then no charges.
	patch.time_left = 0.1
	await _frames(20)
	_check(not patch.active, "the clock ends the patch")
	_check(patch.charges == 0, "both charges spent")
	await _tap("adversarial_patch")
	_check(not patch.active, "no charge, no patch")
	far.queue_free()

	# 8. Tag a robot with melee: the squad shoots it.
	patch.charges = 1
	await _tap("adversarial_patch")
	var victim := _sentry(Vector3(0, 0, -1.6), Vector3.ZERO)
	var squad := _sentry(Vector3(-8, 0, -1.6), Vector3(0, 0, -1.6))
	await _frames(4)
	await _tap("melee")
	await _frames(2)
	_check(victim.mislabeled_t > 0.0 and victim.collision_layer == 2, "melee tags the robot (layer %d)" % victim.collision_layer)
	_check(not patch.active, "tagging hands the patch over")
	var hp0: float = victim.hp.current_health
	victim.hp.apply_damage(10.0, squad) # squad fire, robot on robot
	_check(victim.hp.current_health < hp0, "a tagged robot takes squad fire (%.0f -> %.0f)" % [hp0, victim.hp.current_health])
	squad.state = EnemyBase.State.IDLE
	squad.target = null
	await _frames(6)
	_check(squad.target == victim, "squad retargets the tagged robot")
	victim.mislabeled_t = 0.05
	await _frames(10)
	_check(victim.mislabeled_t <= 0.0 and victim.collision_layer == 4, "tag wears off and the layer comes back")
	victim.queue_free()
	squad.queue_free()

	# 9. Vision scanner.
	var scanner: Node3D = (load("res://scripts/systems/vision_scanner.gd") as GDScript).new()
	get_tree().root.add_child(scanner)
	scanner.global_position = Vector3(0, 5.5, -12) # head on its mast: the 24 deg tilt lands on the chest
	await _frames(4)
	scanner.process_mode = Node.PROCESS_MODE_DISABLED # hold the aim, no sweep
	scanner.call("_face", player.global_position + Vector3.UP * 1.2, 1.0)
	await _frames(2)
	var saw_plain: bool = scanner.call("_sees", player)
	patch.charges = 1
	await _tap("adversarial_patch")
	var saw_patched: bool = scanner.call("_sees", player)
	print("scanner: plain=%s patched=%s" % [saw_plain, saw_patched])
	_check(saw_plain and not saw_patched, "vision scanner ignores a patched player at 12 m")

	print("RESULT %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
