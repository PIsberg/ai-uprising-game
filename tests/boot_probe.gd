extends Node
## Simulates app boot: with nothing pending, enter the loading screen — it should
## show the AI UPRISING title then load the main menu.
func _ready() -> void:
	await get_tree().process_frame
	var cap: Node = load("res://tests/boot_capture.gd").new()
	get_tree().root.add_child(cap)
	GameState.pending_scene = "" # boot state
	get_tree().change_scene_to_file("res://scenes/ui/loading_screen.tscn")
