extends Node3D
## Buys a spread of upgrades, THEN loads a level so the HUD builds its upgrade-chip
## row from the run state. Confirms only bought tracks show (with the right rank),
## and screenshots the chips above the health bar.

func _ready() -> void:
	GameState.reset_run()
	GameState.score = 999999
	GameState.buy_upgrade("damage"); GameState.buy_upgrade("damage")          # 2
	GameState.buy_upgrade("blast"); GameState.buy_upgrade("blast"); GameState.buy_upgrade("blast") # 3
	GameState.buy_upgrade("leech")                                            # 1
	GameState.buy_upgrade("stamina"); GameState.buy_upgrade("stamina")        # 2
	# mag + reload left at 0 — they must NOT show a chip.

	var lvl: Node = (load("res://scenes/levels/level_hivemind.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.0).timeout

	var row := lvl.find_child("UpgradeRow", true, false)
	var n := row.get_child_count() if row else -1
	print("UPGRADE CHIPS: %d (expected 4: damage/blast/leech/stamina)" % n)

	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/hud_upgrades.png")
	print("HUD_UPGRADE_PROBE_DONE")
	get_tree().quit()
