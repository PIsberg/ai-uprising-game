extends Node
## One-shot: prints the resolved GraphicsSettings render scale + scaling mode.
## Used to verify the first-run auto render-scale on high-res screens.
func _ready() -> void:
	await get_tree().process_frame
	var vp := get_viewport()
	print("CHECK screen=%s render_scale=%.2f vp_scale=%.2f mode=%d" % [
		DisplayServer.screen_get_size(), GraphicsSettings.render_scale,
		vp.scaling_3d_scale, vp.scaling_3d_mode])
	get_tree().quit()
