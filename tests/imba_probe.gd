extends Node3D
## Types "imba" into the live player and checks the cheat: every upgrade track
## maxes, the stamina pool is applied immediately, and the HUD upgrade chips
## rebuild to show all six. Screenshots the result.

func _ready() -> void:
	GameState.reset_run() # start with nothing
	var lvl: Node = (load("res://scenes/levels/level_hivemind.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.0).timeout
	var player := get_tree().get_first_node_in_group("player")
	var row0 := lvl.find_child("UpgradeRow", true, false)
	print("BEFORE: chips=%d damage_lvl=%d stamina=%.0f" % [
		row0.get_child_count() if row0 else -1, GameState.upgrade_level("damage"), player.max_stamina])

	# Type i-m-b-a as real key events through the player's cheat buffer.
	for ch in "imba":
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.unicode = ch.unicode_at(0)
		player._input(ev)
	await get_tree().process_frame
	await get_tree().process_frame

	var row := lvl.find_child("UpgradeRow", true, false)
	var all_max := true
	for k in GameState.UPGRADE_DEFS:
		if GameState.upgrade_level(k) < GameState.UPGRADE_MAX:
			all_max = false
	print("AFTER: chips=%d all_maxed=%s damage_lvl=%d stamina=%.0f (base*mult=%.0f)" % [
		row.get_child_count() if row else -1, all_max,
		GameState.upgrade_level("damage"), player.max_stamina, 100.0 * GameState.stamina_mult()])

	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/imba.png")
	print("IMBA_PROBE_DONE")
	get_tree().quit()
