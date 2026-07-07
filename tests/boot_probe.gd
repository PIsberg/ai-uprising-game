extends Node
func _ready() -> void:
	await get_tree().process_frame
	var cap: Node = load("res://tests/boot_capture.gd").new()
	get_tree().root.add_child(cap) # survives change_scene
	GameState.start_campaign(GameState.Difficulty.NORMAL)
