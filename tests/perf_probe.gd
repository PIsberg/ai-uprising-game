extends Node
## Dev probe: measures average frame time on a heavy interior level at each
## graphics tier (set via PERF_TIER env var: 0/1/2), printing a PERF line.
## Run windowed:  PERF_TIER=0 godot --path . res://tests/perf_probe.tscn

const WARMUP_FRAMES := 90   # let shaders compile / navmesh bake settle
const MEASURE_FRAMES := 240

var _restore_tier: int = 2

func _ready() -> void:
	# Uncapped + no vsync, or every tier reads as the monitor refresh rate.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_restore_tier = GraphicsSettings.tier()
	var tier := int(OS.get_environment("PERF_TIER")) if OS.get_environment("PERF_TIER") != "" else 2
	# quality var directly + viewport apply, NOT set_quality(): the probe must
	# never persist its temporary tier into the player's settings.cfg.
	GraphicsSettings.quality = tier
	GraphicsSettings._apply_viewport()
	var lvl: PackedScene = load("res://scenes/levels/level_gpt.tscn")
	add_child(lvl.instantiate())
	_measure(tier)

func _measure(tier: int) -> void:
	for i in WARMUP_FRAMES:
		await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	for i in MEASURE_FRAMES:
		await get_tree().process_frame
	var dt := (Time.get_ticks_usec() - t0) / 1000000.0
	print("PERF tier=%d (%s): %.1f fps avg over %d frames" % [
		tier, GraphicsSettings.quality_label(), MEASURE_FRAMES / dt, MEASURE_FRAMES])
	GraphicsSettings.quality = _restore_tier # in-memory only; cfg was never touched
	get_tree().quit()
