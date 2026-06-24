extends Control
## Windowed probe: render the campaign map with progress + a hovered unlocked
## sector so the intel panel shows hostiles/objective. godot --path . res://tests/map_shot.tscn
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var map: Control = (load("res://scenes/ui/campaign_map.tscn") as PackedScene).instantiate()
	add_child(map)
	await get_tree().process_frame
	map._frontier = 11   # force ~2/3 unlocked, overriding any save
	map._relayout()
	await get_tree().process_frame
	map._hover_node(4)   # an unlocked, non-boss sector → full intel
	for i in 24:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/map_shot.png")
	print("SAVED map_shot.png")
	get_tree().quit()
