extends Node
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var ps: PackedScene = load("res://scenes/ui/main_menu.tscn")
	var menu := ps.instantiate()
	get_tree().root.add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	menu._open_level_select() # simulate the "warp" cheat
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/menu_warp.png")
	print("SAVED menu_warp")
	get_tree().quit()
