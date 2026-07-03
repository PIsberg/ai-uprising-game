extends Node
## Dev probe: runs the comic intro and captures the assembled three-panel page
## (~4.2s in, after all panels have slid into place) to user://comic_page.png,
## then quits. Run windowed:
##   godot --path . res://tests/comic_page_probe.tscn

func _ready() -> void:
	var cs: PackedScene = load("res://scenes/cutscene/comic_intro.tscn")
	add_child(cs.instantiate())
	await get_tree().create_timer(4.2).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/comic_page.png")
	print("SAVED comic_page.png")
	print("RESULT PASS")
	get_tree().quit()
