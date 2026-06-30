extends Node
## Loads each listed level, warms up, and prints render stats (fps, draw calls,
## objects, primitives, video memory) — a baseline to find perf hotspots and to
## prove an optimization is visually free. Run windowed:
##   godot --path . tools/perf_measure.tscn

const LEVELS := ["gpt", "01", "titan", "neon"]
const WARMUP := 60
const MEASURE := 150

var _i := 0


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DisplayServer.window_set_size(Vector2i(1280, 720))
	if GraphicsSettings:
		GraphicsSettings.quality = 2          # highest tier (in-memory only)
		GraphicsSettings._apply_viewport()
	await _run()
	get_tree().quit()


func _run() -> void:
	for id in LEVELS:
		var holder := Node3D.new()
		add_child(holder)
		var lvl: Node = load("res://scenes/levels/level_%s.tscn" % id).instantiate()
		holder.add_child(lvl)
		for f in WARMUP:
			await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		for f in MEASURE:
			await get_tree().process_frame
		var dt := (Time.get_ticks_usec() - t0) / 1000000.0
		var rs := RenderingServer
		var draws := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var objs := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		var prims := rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		var vmem := rs.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0
		print("PERF %-12s fps=%6.1f draws=%5d objects=%5d prims=%8d vmem=%6.1fMB" % [
			id, MEASURE / dt, draws, objs, prims, vmem])
		holder.free()
		await get_tree().process_frame
