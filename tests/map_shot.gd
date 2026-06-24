extends Control
## Windowed probe: campaign map driven by the KEYBOARD cursor — shows the
## selection reticle + intel for the cursor's sector. godot --path . res://tests/map_shot.tscn
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var map: Control = (load("res://scenes/ui/campaign_map.tscn") as PackedScene).instantiate()
	add_child(map)
	await get_tree().process_frame
	map._frontier = 11
	map._relayout()
	await get_tree().process_frame
	map._sel = 11
	map._move_sel(-4)    # arrow-key left x4 → cursor lands on sector 8 (a boss)
	for i in 24:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/map_shot.png")
	print("SAVED  sel=", map._sel, " active=", map._active())
	get_tree().quit()
