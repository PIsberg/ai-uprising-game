extends Node
## Dev probe: captures the victory ("SECTOR CLEARED") screen with the new
## mission-debrief line (KILLS / DEATHS — time/accuracy already live on the
## grade line above it), fed known stats so the rendered numbers can be
## checked against the source values by eye.
## Run WINDOWED (headless renders black):
##   godot --path . res://tests/debrief_shot.tscn --quit-after 60

func _ready() -> void:
	if has_node("/root/GraphicsSettings"):
		get_node("/root/GraphicsSettings").set_quality(1)
	add_child((load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate())
	await get_tree().create_timer(1.6).timeout # let the builder finish + navmesh bake
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free() # keep the frame calm — this probe is about the win screen, not combat
	# Feed GameState known per-level stats matching the task's worked example
	# (TIME 03:41 / KILLS 23 / ACCURACY 61% / DEATHS 1) so the rendered block
	# can be checked against the numbers that produced it.
	GameState.current_level_path = "res://scenes/levels/level_gpt.tscn"
	GameState.kills = 23
	GameState.stat_shots = 41
	GameState.stat_hits = 25          # 25/41 = 60.97% -> displays 61%
	GameState.level_deaths = 1
	GameState.level_start_ms = Time.get_ticks_msec() - 221000 # 3m41s ago
	GameState.on_level_complete() # drives grade_level() + the HUD's win menu, same as a real clear
	await get_tree().create_timer(0.3).timeout
	RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/df4a3e78-e161-445d-96b9-6124bf321864/scratchpad/debrief.png"
	img.save_png(path)
	print("SAVED ", path)
	get_tree().quit()
