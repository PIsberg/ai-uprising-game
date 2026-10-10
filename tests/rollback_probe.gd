extends Node
## Probe: the ROLLBACK robot restores dead robots from a checkpoint (enemy_rollback.gd).
## (1) it is wired: level builder, codex, one on HIVEMIND and one on SUBLEVEL;
## (2) a robot killed within WATCH_RANGE leaves a checkpoint; a live ROLLBACK
##     plants itself after RESTORE_GAP, channels (beam, rewind column, status),
##     and when CHANNEL_TIME is up the same chassis is back where it fell:
##     marked restored, worth RESTORED_SCORE, off the enemy layer while it
##     rebuilds, then whole (its own materials, no dissolve) and on the layer;
## (3) no checkpoint for a disintegrated robot, a boss-sized one, one out of
##     range, or a restored robot killed again;
## (4) INTERRUPT_DMG on the ROLLBACK mid-channel corrupts the checkpoint: the
##     channel ends and nothing comes back; an EMP does the same;
## (5) checkpoints older than CHECKPOINT_TTL are dropped;
## (6) its death mid-channel ends the rewind and restores nothing.
##   godot --headless --path . --audio-driver Dummy res://tests/rollback_probe.tscn

const SCENE := "res://scenes/enemies/rollback.tscn"
const ANDROID := "res://scenes/enemies/android.tscn"
const DISSOLVE := preload("res://shaders/dissolve.gdshader")
var ok := true
var rb: EnemyRollback

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## Waits up to `max_frames` physics frames for `cond`; true if it came true.
func _until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()

func _ready() -> void:
	_run.call_deferred()

func _count(level: String) -> int:
	var n := 0
	for en in LevelDefs.get_def(level).get("enemies", []):
		if en.get("type", "") == "rollback":
			n += 1
	return n

## A posed android (no AI, still dies normally).
func _robot(pos: Vector3) -> EnemyBase:
	var e: EnemyBase = (load(ANDROID) as PackedScene).instantiate()
	add_child(e)
	e.global_position = pos
	e.set_physics_process(false)
	return e

func _restored() -> Array:
	return get_tree().get_nodes_in_group("enemy").filter(func(n: Node) -> bool:
		return n.has_meta(&"restored") and (n as EnemyBase).state != EnemyBase.State.DEAD)

func _kill(e: EnemyBase, style: int = KillFx.NONE) -> void:
	if style != KillFx.NONE:
		KillFx.tag(e.hp, style)
	e.hp.apply_damage(99999.0, null)
	KillFx.untag(e.hp)

func _uses_dissolve(e: Node) -> bool:
	for n in e.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m and m.shader == DISSOLVE:
				return true
	return false

## Kills a fresh android beside the ROLLBACK and waits for the channel to start.
func _start_channel(pos: Vector3) -> bool:
	var e := _robot(pos)
	await _frames(int(EnemyRollback.WATCH_EVERY * 60.0) + 4)
	_kill(e)
	return await _until(func() -> bool: return rb.channeling, int((EnemyRollback.RESTORE_GAP + 1.0) * 60.0))

func _run() -> void:
	# 1. Wiring.
	_check("level builder knows rollback", LevelBuilder.ENEMY_SCENES.get("rollback", "") == SCENE)
	_check("codex entry", EnemyCodex.has("rollback") and "rollback" in EnemyCodex.ORDER)
	_check("one on HIVEMIND", _count("hivemind") == 1, str(_count("hivemind")))
	_check("one on SUBLEVEL", _count("sublevel") == 1, str(_count("sublevel")))

	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(200, 1, 200)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	# The player is out of sight: the ROLLBACK idles where it stands.
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var php := Damageable.new()
	php.name = "Damageable"
	php.max_health = 1000000.0
	player.add_child(php)
	add_child(player)
	player.global_position = Vector3(0, 0, 90)

	rb = (load(SCENE) as PackedScene).instantiate()
	add_child(rb)
	rb.global_position = Vector3.ZERO
	var a := _robot(Vector3(6, 0, 0))
	var a_scene := a.scene_file_path
	var a_score := a.score_value
	await _frames(int(EnemyRollback.WATCH_EVERY * 60.0) + 4)

	# 2. Checkpoint, channel, restore.
	_kill(a)
	_check("a nearby kill leaves a checkpoint", rb.checkpoints.size() == 1
			and (rb.checkpoints[0]["pos"] as Vector3).distance_to(Vector3(6, 0, 0)) < 0.2, str(rb.checkpoints.size()))
	var began := await _until(func() -> bool: return rb.channeling, int((EnemyRollback.RESTORE_GAP + 1.0) * 60.0))
	_check("it starts rewinding within RESTORE_GAP", began)
	_check("the channel shows a beam, a rewind column and a status", is_instance_valid(rb._beam)
			and is_instance_valid(rb._rewind) and rb.status_text().begins_with("RESTORING"), rb.status_text())
	var back := await _until(func() -> bool: return not _restored().is_empty(), int((EnemyRollback.CHANNEL_TIME + 1.0) * 60.0))
	_check("the robot is back when the channel ends", back and not rb.channeling)
	var r: EnemyBase = _restored()[0] if back else null
	if r:
		_check("same chassis, where it fell", r.scene_file_path == a_scene
				and r.global_position.distance_to(Vector3(6, 0, 0)) < 0.3, "%s at %s" % [r.scene_file_path, r.global_position])
		_check("worth RESTORED_SCORE", r.score_value == int(a_score * EnemyRollback.RESTORED_SCORE), str(r.score_value))
		_check("untouchable while it rebuilds", r.collision_layer == 0 and _uses_dissolve(r))
		await _frames(int(EnemyRollback.REBUILD_TIME * 60.0) + 10)
		_check("whole again: own materials, on the enemy layer", r.collision_layer == 4 and not _uses_dissolve(r),
				"layer %d" % r.collision_layer)
	_check("one restore spent", rb.restores_left == EnemyRollback.RESTORES_MAX - 1, str(rb.restores_left))

	# 3. No checkpoint.
	var d := _robot(Vector3(-6, 0, 0))
	var boss := _robot(Vector3(0, 0, 6))
	boss.score_value = 1000
	var far := _robot(Vector3(0, 0, -(EnemyRollback.WATCH_RANGE + 8.0)))
	await _frames(int(EnemyRollback.WATCH_EVERY * 60.0) + 4)
	_kill(d, KillFx.DISINTEGRATE)
	_kill(boss)
	_kill(far)
	if r:
		_kill(r)
	_check("no checkpoint for disintegrated, boss-sized, out of range or already restored",
			rb.checkpoints.is_empty(), str(rb.checkpoints.size()))

	# 4. Interrupted.
	await _frames(int(EnemyRollback.RESTORE_GAP * 60.0) + 4)
	var n0 := _restored().size()
	_check("a second kill starts a second rewind", await _start_channel(Vector3(5, 0, 4)))
	rb.hp.apply_damage(EnemyRollback.INTERRUPT_DMG + 5.0, player)
	_check("INTERRUPT_DMG mid-channel ends it", not rb.channeling and not is_instance_valid(rb._beam))
	await _frames(int((EnemyRollback.CHANNEL_TIME + 0.5) * 60.0))
	_check("the corrupted checkpoint restores nothing", _restored().size() == n0 and rb.checkpoints.is_empty())
	_check("an EMP mid-channel ends it too", await _start_channel(Vector3(-5, 0, 4)))
	rb._emp_t = 1.0
	await _frames(3)
	_check("signal lost: no rewind", not rb.channeling)
	rb._emp_t = 0.0
	_check("an interrupted restore costs nothing", rb.restores_left == EnemyRollback.RESTORES_MAX - 1, str(rb.restores_left))

	# 5. TTL.
	rb.checkpoints.append({"scene": ANDROID, "pos": Vector3(3, 0, 3), "yaw": 0.0, "mults": [1.0, 1.0, 1.0, 0.3],
			"at_ms": Time.get_ticks_msec() - int((EnemyRollback.CHECKPOINT_TTL + 1.0) * 1000.0), "parent": self})
	_check("a stale checkpoint is dropped", rb.pick_checkpoint().is_empty() and rb.checkpoints.is_empty())

	# 6. Death mid-channel.
	await _frames(int(EnemyRollback.RESTORE_GAP * 60.0) + 4)
	n0 = _restored().size()
	_check("a third rewind starts", await _start_channel(Vector3(4, 0, -4)))
	rb.hp.apply_damage(99999.0, player)
	await _frames(3)
	_check("its death ends the rewind", not rb.channeling and not is_instance_valid(rb._rewind))
	await _frames(int((EnemyRollback.CHANNEL_TIME + 0.5) * 60.0))
	_check("and restores nothing", _restored().size() == n0)

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
