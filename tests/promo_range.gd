extends Node
## Promo: the firing range (real FPS gameplay view). Saves docs/screenshots/firing_range.png
func _ready() -> void:
	add_child((load("res://scenes/levels/level_range.tscn") as PackedScene).instantiate())
	for i in 70:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var th := int(round(1600.0 * img.get_height() / float(img.get_width())))
	img.resize(1600, th, Image.INTERPOLATE_LANCZOS)
	img.save_png("res://docs/screenshots/firing_range.png")
	print("SAVED firing_range 1600x", th)
	get_tree().quit()
