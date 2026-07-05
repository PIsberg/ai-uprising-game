extends Node
## Opens the main menu, switches to the Settings panel, and screenshots it —
## verifies every option fits on screen (two-column grid, Back visible).
##   godot --path . --quit-after 600 res://tools/settings_menu_shot.tscn

const SHOT := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/df4a3e78-e161-445d-96b9-6124bf321864/scratchpad/settings_menu.png"

func _ready() -> void:
	var menu: Node = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu._on_settings_pressed()
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(SHOT)
	print("SAVED ", SHOT)
	get_tree().quit()
