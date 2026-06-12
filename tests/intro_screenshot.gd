extends Node
## Dev probe: runs the intro cutscene and captures two frames — the calm chore
## phase (~3s) and just after the turn (~16s) — to user://intro_calm.png and
## user://intro_turn.png, then quits. Run windowed:
##   godot --path . res://tests/intro_screenshot.tscn

func _ready() -> void:
	GameState.intro_played = false # the cutscene self-frees if it thinks it ran
	var cs: PackedScene = load("res://scenes/cutscene/intro_cutscene.tscn")
	add_child(cs.instantiate())
	await get_tree().create_timer(3.0).timeout
	_snap("intro_calm.png")
	await get_tree().create_timer(13.5).timeout # past the 14.5s turn beat
	_snap("intro_turn.png")
	print("DONE")
	get_tree().quit()

func _snap(fname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/" + fname)
	print("SAVED ", fname)
