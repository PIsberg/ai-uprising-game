extends Control
## Promo: campaign map + armory shop. Saves docs/screenshots/{campaign_map,armory}.png
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# --- campaign map ---
	var map: Control = (load("res://scenes/ui/campaign_map.tscn") as PackedScene).instantiate()
	add_child(map)
	await get_tree().process_frame
	map._frontier = 11
	map._relayout()
	await get_tree().process_frame
	map._hover_node(4)
	for i in 20:
		await get_tree().process_frame
	await _save("campaign_map")
	map.queue_free()
	await get_tree().process_frame
	# --- armory shop ---
	GameState.score = 5200
	GameState.upgrades = {"damage": 2, "mag": 0, "reload": 5}
	GameState.supply_ammo = 120; GameState.supply_grenades = 0; GameState.supply_health = 40.0
	var shop := Armory.new()
	add_child(shop)
	for i in 30:
		await get_tree().process_frame
	await _save("armory")
	get_tree().quit()

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var th := int(round(1600.0 * img.get_height() / float(img.get_width())))
	img.resize(1600, th, Image.INTERPOLATE_LANCZOS)
	img.save_png("res://docs/screenshots/%s.png" % name)
	print("SAVED ", name, " 1600x", th)
