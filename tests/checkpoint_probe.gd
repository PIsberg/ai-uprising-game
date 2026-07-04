extends Node
## Headless probe for the mid-level checkpoint / respawn flow (see GameState's
## checkpoint section + Player.checkpoint_snapshot/respawn_from_checkpoint).
## Fakes a task completion — the real in-game trigger a level uses (see
## GameState.complete_task) — then drains ammo, hurts, and RELOCATES the player
## before killing them, and asserts a checkpoint respawn restores position /
## the HP floor / ammo IN PLACE (no scene reload) while the completed task
## stays completed (a death must never undo world state — that's the whole
## anti-farming point).
##   godot --headless --path . res://tests/checkpoint_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var lvl := (load("res://scenes/levels/level_01.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(lvl)
	await get_tree().create_timer(2.0).timeout
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	var fails := 0
	if player == null:
		print("FAIL: no player")
		print("RESULT FAIL")
		get_tree().quit(1)
		return

	# --- 1) No checkpoint yet at level start (only a task/boss beat sets one) ---
	if GameState.has_checkpoint():
		print("FAIL: checkpoint already set before any task completed")
		fails += 1

	# --- 2) Completing a task is the real in-game checkpoint trigger ---
	GameState.register_task("probe_task", "Probe Task")
	GameState.complete_task("probe_task")
	if not GameState.has_checkpoint():
		print("FAIL: complete_task() did not set a checkpoint")
		fails += 1
	var ckpt_pos: Vector3 = player.global_position

	# Drain ammo + hurt (not lethally) so the restore is provable, not a no-op.
	var w: Weapon = player.get_node_or_null("Head/Camera3D/WeaponHolder").get("current") \
		if player.get_node_or_null("Head/Camera3D/WeaponHolder") else null
	if w:
		w.mag = 0
		w.reserve = 0
	player.hp.current_health = 5.0

	# --- 3) Wander away, then die — respawn must bring the player BACK to the
	# checkpoint, not leave them wherever they fell. ---
	player.global_position += Vector3(12.0, 0.0, 8.0)
	await get_tree().physics_frame
	player.hp.apply_damage(9999.0, null)
	await get_tree().create_timer(0.2).timeout
	if not player.get("_dead"):
		print("FAIL: player did not register as dead")
		fails += 1
	if GameState.current_state != GameState.State.GAME_OVER:
		print("FAIL: GameState did not enter GAME_OVER on death")
		fails += 1

	# --- 4) Respawn at the checkpoint — what the HUD's TRY AGAIN / SPACE does
	# once GameState.has_checkpoint() is true (see hud.gd _on_death_restart_pressed) ---
	GameState.respawn_at_checkpoint()
	await get_tree().create_timer(0.1).timeout

	if player.get("_dead"):
		print("FAIL: still dead after respawn_at_checkpoint()")
		fails += 1
	if GameState.current_state != GameState.State.PLAYING:
		print("FAIL: GameState not back in PLAYING after respawn")
		fails += 1
	var dist: float = player.global_position.distance_to(ckpt_pos)
	if dist > 0.5:
		print("FAIL: respawned %.2fm from the checkpoint, expected ~0" % dist)
		fails += 1
	var hp_frac: float = player.hp.current_health / player.hp.max_health
	if hp_frac < 0.5 - 0.01:
		print("FAIL: respawn HP fraction %.2f below the 0.5 floor" % hp_frac)
		fails += 1
	if w and (w.mag <= 0 or w.reserve <= 0):
		print("FAIL: ammo not restored on respawn (mag=%d reserve=%d)" % [w.mag, w.reserve])
		fails += 1
	var head := player.get_node("Head") as Node3D
	if rad_to_deg(absf(head.rotation.z)) > 5.0:
		print("FAIL: head still in the fall-over pose after respawn (roll=%.1fdeg)" % rad_to_deg(head.rotation.z))
		fails += 1

	# --- 5) World state persists: the completed task is still done, not undone
	# by the death (dying gets you back on your feet — it doesn't farm a reset). ---
	if not GameState.is_task_done("probe_task"):
		print("FAIL: task un-completed by a death — world state should never reset")
		fails += 1

	print("CHECKPOINT dist=%.2fm hp_frac=%.2f ammo_mag=%s dead=%s state=%s task_done=%s" % [
		dist, hp_frac, (str(w.mag) if w else "n/a"), str(player.get("_dead")),
		str(GameState.current_state), str(GameState.is_task_done("probe_task"))])
	print("RESULT ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(fails)
