extends Node
## Dev probe: shows the main menu for a moment and captures a frame to
## user://menu.png, then quits. Run windowed:
##   godot --path . res://tests/menu_screenshot.tscn

func _ready() -> void:
	var ms: PackedScene = load("res://scenes/ui/main_menu.tscn")
	add_child(ms.instantiate())
	await get_tree().create_timer(1.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/menu.png")
	print("SAVED menu.png")
	print("DONE")
	get_tree().quit()
