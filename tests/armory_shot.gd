extends Node
## Windowed probe: render the Armory shop (upgrades + field supplies). godot --path . res://tests/armory_shot.tscn
func _ready() -> void:
	GameState.score = 5200
	GameState.upgrades = {"damage": 2, "mag": 0, "reload": 5}  # partial / empty / MAXED
	GameState.supply_ammo = 120   # 2 crates queued
	GameState.supply_grenades = 0
	GameState.supply_health = 40.0
	var a := Armory.new()
	add_child(a)
	for i in 34:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/armory_shot.png")
	print("SAVED armory_shot.png")
	get_tree().quit()
