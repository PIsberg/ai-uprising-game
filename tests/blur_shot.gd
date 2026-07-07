extends Node3D
## Clean high-res indoor capture to diagnose "indoor looks blurry" — no probe
## banners, forced HIGH quality + full render scale, eye-level framing.

func _ready() -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs:
		gs.call("set_render_scale", 1.0)
		if gs.has_method("set_quality"):
			gs.call("set_quality", 2) # HIGH
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.0).timeout
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		var cam := get_viewport().get_camera_3d()
		if cam:
			print("render_scale=%.2f msaa=%d taa=%s ssaa=%d" % [
				get_viewport().scaling_3d_scale, get_viewport().msaa_3d,
				get_viewport().use_taa, get_viewport().screen_space_aa])
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/blur_diag.png")
	print("BLUR_SHOT_DONE")
	get_tree().quit()
