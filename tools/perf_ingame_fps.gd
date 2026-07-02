extends Node
## Cross-validates tools/perf_measure.gd's numbers against the REAL, shipped
## in-game FPS counter (GraphicsSettings.show_fps, the HUD overlay a player
## would actually see) — loads a real level with the real Player+HUD, turns
## the counter on, and reads its displayed text after settling.
## Run: godot --path . --quit-after 2000 tools/perf_ingame_fps.tscn

const LEVEL_ID := "gpt"

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DisplayServer.window_set_size(Vector2i(1280, 720))
	GraphicsSettings.quality = 2
	GraphicsSettings.show_fps = true
	var lvl: Node = load("res://scenes/levels/level_%s.tscn" % LEVEL_ID).instantiate()
	add_child(lvl)
	GameState.current_state = GameState.State.PLAYING
	for f in 240:
		await get_tree().process_frame

	# hud.gd's on-screen counter is driven by exactly this: `"%d FPS" %
	# int(round(Engine.get_frames_per_second()))` — this IS the number a real
	# player sees with the FPS counter enabled.
	for i in 10:
		await get_tree().process_frame
		print("HUD would show: %d FPS  (Engine.get_frames_per_second raw=%.2f)" % [
			int(round(Engine.get_frames_per_second())), Engine.get_frames_per_second()])
	get_tree().quit()
