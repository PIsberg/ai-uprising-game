extends Node3D
## Verifies the debrief HIGHLIGHTS: the new engagement systems are counted per
## level and surfaced (with correct singular/plural + streak name) on the grade
## stats + the victory-screen highlights line.

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(1.5).timeout
	GameState.current_state = GameState.State.PLAYING
	GameState.reset_level_stats() # zero the highlight counters for a clean count

	# Fire a spread of the new rewards.
	for i in 3:
		GameState.reward_execution(Vector3.ZERO)
	for i in 2:
		GameState.claim_bounty()
	for i in 5:
		GameState.reward_perfect_dodge()
	# Drive a GODLIKE streak (tier 3 at combo 18).
	while GameState.combo < 18:
		GameState.add_kill(100, "HOSTILE")
		GameState.combo_timer = GameState.COMBO_WINDOW

	var g: Dictionary = GameState.grade_level()
	var s: Dictionary = g["stats"]
	print("stats: exec=%d bounty=%d dodge=%d best_rampage=%d" % [
		s["executions"], s["bounties"], s["dodges"], s["best_rampage"]])

	# Render the highlights line on the HUD and read it back.
	var hud := lvl.get_node("HUD")
	hud.call("_update_debrief_block")
	await get_tree().process_frame
	var hl = hud.get("_highlights_label")
	print("highlights line: '%s'" % (hl.text if hl else "<none>"))

	# Show the victory panel for a screenshot.
	var wm = hud.get("win_menu")
	if wm:
		wm.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/highlights.png")
	print("HIGHLIGHTS_PROBE_DONE")
	get_tree().quit()
