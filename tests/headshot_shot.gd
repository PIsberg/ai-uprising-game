extends Node3D
## Forces the HEADSHOT callout visible to eyeball the new cooler style.

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(1.5).timeout
	var hud := lvl.get_node("HUD")
	hud.set("_headshot_alpha", 1.0)
	hud.set("_headshot_pop", 1.4)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/headshot_style.png")
	print("HEADSHOT_SHOT_DONE")
	get_tree().quit()
