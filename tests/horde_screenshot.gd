extends Node
## Dev probe: loads Last Stand, waits ~8s (first wave spawning, telegraphs up),
## saves user://horde_screenshot.png, quits. Run windowed:
##   godot --path . res://tests/horde_screenshot.tscn

func _ready() -> void:
	var lvl: PackedScene = load("res://scenes/levels/level_horde.tscn")
	add_child(lvl.instantiate())
	_capture()

func _capture() -> void:
	# Wait ~7s wall-clock (frame count is unreliable at low fps on HIGH tier).
	await get_tree().create_timer(7.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/horde_screenshot.png")
	print("SAVED ", OS.get_user_data_dir() + "/horde_screenshot.png")
	get_tree().quit()
