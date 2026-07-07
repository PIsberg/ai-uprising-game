extends Node3D
## Drives the real player in a built level: holds sprint+forward to drain stamina
## to exhaustion, confirms the run speed drops to a walk while locked out, then
## releases and confirms stamina recovers and the lock clears. Also screenshots
## the HUD so the new bar can be eyeballed. Run windowed.

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_sublevel.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.0).timeout
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		print("STAMINA: no player"); get_tree().quit(); return
	player.hp.invulnerable = true
	print("start stamina=%.0f exhausted=%s run_speed=%.1f" % [player._stamina, player._stamina_exhausted, player._current_speed()])

	# ---- DRAIN: start low so exhaustion is reached deterministically despite
	# the player stalling against gate walls (which pauses drain in real play) ----
	player._stamina = 22.0
	Input.action_press("sprint")
	Input.action_press("move_forward")
	var hit_zero := false
	var speed_when_exhausted := -1.0
	for i in range(420): # up to 7 s — enough to bottom out at 20/s
		await get_tree().physics_frame
		# Turn periodically so we don't just pin against a wall and stall.
		if i % 40 == 0:
			player.rotation.y += 1.2
		if player._stamina_exhausted and not hit_zero:
			hit_zero = true
			speed_when_exhausted = player._current_speed()
			break
		if i % 30 == 0:
			print("  drain t=%.2fs stamina=%.0f exhausted=%s hspeed=%.1f run_speed=%.1f" % [
				i / 60.0, player._stamina, player._stamina_exhausted,
				Vector2(player.velocity.x, player.velocity.z).length(), player._current_speed()])
	print("REACHED_EXHAUSTION=%s speed_while_locked=%.1f (walk=%.1f sprint=%.1f)" % [
		hit_zero, speed_when_exhausted, player.walk_speed, player.sprint_speed])

	# ---- RECOVER: release, stand still ----
	Input.action_release("sprint")
	Input.action_release("move_forward")
	var cleared := false
	for i in range(360): # up to 6 s
		await get_tree().physics_frame
		if not player._stamina_exhausted and not cleared:
			cleared = true
			print("  LOCK CLEARED at stamina=%.0f (threshold=%.0f), t=%.2fs" % [
				player._stamina, player.stamina_recover_threshold, i / 60.0])
		if i % 60 == 0:
			print("  recover t=%.1fs stamina=%.0f exhausted=%s" % [i / 60.0, player._stamina, player._stamina_exhausted])
		if player._stamina >= player.max_stamina:
			break
	print("RECOVERED_FULL=%s final_stamina=%.0f" % [player._stamina >= player.max_stamina - 1.0, player._stamina])

	# HUD screenshot (drain partway so the bar is visibly not full).
	Input.action_press("sprint"); Input.action_press("move_forward")
	for i in range(24):
		await get_tree().physics_frame
	Input.action_release("sprint"); Input.action_release("move_forward")
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/stamina_hud.png")
	print("STAMINA_PROBE_DONE")
	get_tree().quit()
