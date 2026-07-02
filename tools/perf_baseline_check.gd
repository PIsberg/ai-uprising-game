extends Node
## Sanity check for tools/perf_measure.gd: measures raw engine/window FPS with
## NOTHING loaded (empty scene), using the identical harness (same warmup/
## measure frame counts, same window/vsync setup). If this reports low FPS
## too, the low numbers from perf_measure are a measurement artifact (e.g.
## window-focus throttling), not real level-rendering cost.
const WARMUP := 60
const MEASURE := 150

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DisplayServer.window_set_size(Vector2i(1280, 720))
	for f in WARMUP:
		await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	for f in MEASURE:
		await get_tree().process_frame
	var dt := (Time.get_ticks_usec() - t0) / 1000000.0
	print("PERF_BASELINE empty-scene fps=%.1f" % (MEASURE / dt))
	get_tree().quit()
