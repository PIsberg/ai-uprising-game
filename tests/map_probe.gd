extends Control
## Dev probe: screenshots the campaign map with the whole campaign unlocked, so the
## new sectors (lava/water), their hazard rings, the act grouping and the drifting
## motes can be eyeballed. Run WINDOWED:
##   godot --path . res://tests/map_probe.tscn

const OUT := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private/4fbdff7a-4323-435c-af31-9542c7153dc8/scratchpad/campaign_map.png"

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Unlock the whole campaign so every sector (incl. the new ones) renders lit.
	GameState.max_level_reached = GameState.campaign().size() - 1
	GameState.level_index = GameState.max_level_reached
	var map: Control = load("res://scenes/ui/campaign_map.tscn").instantiate()
	add_child(map)
	_shoot.call_deferred()

func _shoot() -> void:
	await get_tree().create_timer(1.0).timeout # let layout + animation settle
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT)
	print("SAVED ", OUT)
	get_tree().quit()
