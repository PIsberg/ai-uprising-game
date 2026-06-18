extends Control
## Dev probe: show the campaign map with a mid-run progress state and screenshot
## it. Run windowed:
##   godot --path . res://tests/campaign_map_probe.tscn

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Pretend we've cleared up to (and including) the GOLIATH boss + a couple more.
	GameState.clear_save()
	GameState.max_level_reached = 7
	var map: Control = (load("res://scenes/ui/campaign_map.tscn") as PackedScene).instantiate()
	add_child(map)
	map.set_anchors_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	await get_tree().process_frame
	if map.has_method("_relayout"):
		map._relayout()
	await get_tree().create_timer(0.4).timeout
	RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/campaign_map.png")
	print("SAVED campaign_map.png frontier=", GameState.max_level_reached)
	get_tree().quit()
