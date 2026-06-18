extends Node
## Dev probe: confirm the pause-menu Mouse Sensitivity slider exists, persists to
## GraphicsSettings, and updates the live player. Run windowed:
##   godot --path . res://tests/sens_probe.tscn

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if has_node("/root/GraphicsSettings"):
		get_node("/root/GraphicsSettings").set_quality(1)
	var level: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(level)
	await get_tree().create_timer(1.6).timeout
	var player := get_tree().get_first_node_in_group("player")

	# Locate the slider by its row label.
	var pause := level.find_child("PauseMenu", true, false)
	var slider: HSlider = null
	for row in pause.get_node("VBox").get_children():
		if row is HBoxContainer:
			var has_label := false
			var sl: HSlider = null
			for c in row.get_children():
				if c is Label and "Sensitiv" in (c as Label).text:
					has_label = true
				if c is HSlider:
					sl = c
			if has_label:
				slider = sl
	print("SENS slider_found=", slider != null)
	if slider == null:
		get_tree().quit(); return

	var gs := get_node("/root/GraphicsSettings")
	slider.value = 2.4
	await get_tree().process_frame
	print("SENS after_change gs=%.2f player=%.2f match=%s" % [
		gs.sensitivity, player.get("_look_sens_mult"),
		str(is_equal_approx(gs.sensitivity, 2.4) and is_equal_approx(player.get("_look_sens_mult"), 2.4))])

	# Show the pause menu for a screenshot.
	GameState.set_state(GameState.State.PAUSED)
	if pause.has_method("set"):
		pause.visible = true
	await get_tree().create_timer(0.4).timeout
	RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/sens_pause.png")
	print("SAVED sens_pause.png")
	get_tree().quit()
