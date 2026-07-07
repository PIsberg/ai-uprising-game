extends Node3D
## Verifies the melee EXECUTION finisher: a shove into a low-HP non-boss instakills
## it + fires the execution reward, while a healthy enemy just takes the shove damage.

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.0).timeout
	GameState.current_state = GameState.State.PLAYING
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var cam := get_viewport().get_camera_3d()
	var fwd := -cam.global_transform.basis.z

	# Grab two live non-boss enemies to test both branches.
	var live: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and e.score_value < 1000 and e.hp != null and e.hp.is_alive():
			live.append(e)
	if live.size() < 2:
		print("not enough enemies: %d" % live.size()); get_tree().quit(); return

	var exec_fired := [0]
	GameState.execution.connect(func(_p): exec_fired[0] += 1)

	# --- EXECUTE: weakened enemy in the cone -> instakill + reward ---
	var weak: EnemyBase = live[0]
	weak.global_position = cam.global_position + fwd * 1.6
	weak.hp.current_health = 20.0 # below execute_hp_threshold (40)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.call("_do_melee")
	await get_tree().process_frame
	print("execute case: enemy_alive=%s exec_signals=%d (expect dead, 1)" % [
		weak.hp.is_alive(), exec_fired[0]])

	# Screenshot the EXECUTED! banner while it's fresh.
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/execute.png")

	# --- SHOVE: healthy enemy -> survives, NO execution ---
	exec_fired[0] = 0
	var healthy: EnemyBase = live[1]
	healthy.global_position = cam.global_position + fwd * 1.6
	healthy.hp.current_health = 100.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.call("_do_melee")
	await get_tree().process_frame
	print("shove case: enemy_alive=%s hp=%.0f exec_signals=%d (expect alive, ~72, 0)" % [
		healthy.hp.is_alive(), healthy.hp.current_health, exec_fired[0]])
	print("EXECUTE_PROBE_DONE")
	get_tree().quit()
