extends Node3D
## Verifies the RAMPAGE kill-streak power loop: chaining kills spikes the player
## into escalating tiers (damage/fire/speed buffs + a heal + banner), and it all
## collapses when the streak breaks.

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(1.5).timeout
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var d = player.get_node("Damageable")
	d.current_health = 40.0
	GameState._reset_combo()

	# Chain kills to hit tier 1 (5), 2 (10), 3 (18).
	for target_combo in [5, 10, 18]:
		while GameState.combo < target_combo:
			GameState.add_kill(100, "HOSTILE")
			GameState.combo_timer = GameState.COMBO_WINDOW # keep the window open
		print("combo=%d tier=%d dmg=%.2f fire=%.2f speed=%.2f hp=%.0f" % [
			GameState.combo, GameState.rampage_tier, GameState.rampage_damage_mult(),
			GameState.rampage_fire_mult(), GameState.rampage_speed_mult(), d.current_health])

	# Screenshot the GODLIKE banner (freshly punched in).
	get_tree().root.get_node("RampageProbe") # keep alive
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/rampage.png")

	# Break the streak: let the combo window lapse -> everything collapses to 1.0.
	GameState.combo_timer = 0.01
	await get_tree().create_timer(0.2).timeout
	print("after streak break: tier=%d dmg=%.2f fire=%.2f speed=%.2f" % [
		GameState.rampage_tier, GameState.rampage_damage_mult(),
		GameState.rampage_fire_mult(), GameState.rampage_speed_mult()])
	print("RAMPAGE_PROBE_DONE")
	get_tree().quit()
