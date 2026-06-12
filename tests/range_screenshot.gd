extends Node
## Dev probe: loads the gun range, waits for the builder + a few frames, then
## saves user://range_screenshot.png and quits. Run windowed:
##   godot --path . res://tests/range_screenshot.tscn

func _ready() -> void:
	var lvl: PackedScene = load("res://scenes/levels/level_range.tscn")
	add_child(lvl.instantiate())
	_capture()

func _capture() -> void:
	for i in 40:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/range_screenshot.png")
	print("SAVED ", OS.get_user_data_dir() + "/range_screenshot.png")
	get_tree().quit()
