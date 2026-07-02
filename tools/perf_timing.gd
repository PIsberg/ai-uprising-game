extends Node
## Breaks down WHERE frame time actually goes (process/physics/nav/audio vs.
## render) so we know whether the fps drop is CPU script cost or GPU cost —
## the earlier bisect showed disabling SSAO/SSIL/SSR/fog/glow/shadows barely
## moved the needle, which points at a CPU-side (or shader-compile-stall) cause
## rather than the screen-space effects themselves.
## Run: godot --path . --quit-after 3000 tools/perf_timing.tscn

const LEVEL_ID := "gpt"

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DisplayServer.window_set_size(Vector2i(1280, 720))
	if GraphicsSettings:
		GraphicsSettings.quality = 2
		GraphicsSettings._apply_viewport()
	var lvl: Node = load("res://scenes/levels/level_%s.tscn" % LEVEL_ID).instantiate()
	add_child(lvl)

	# Sample every 10 frames for a long window so we can see whether cost is
	# STEADY (a real per-frame cost) or STALLS early then settles (a
	# shader-compile / navmesh-bake hitch).
	for f in 300:
		await get_tree().process_frame
		if f % 10 == 0:
			var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			var nav_ms := Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0
			var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			var fps := Performance.get_monitor(Performance.TIME_FPS)
			print("f=%3d fps=%6.1f process_ms=%6.2f physics_ms=%6.2f nav_ms=%6.2f draws=%d" % [
				f, fps, proc_ms, phys_ms, nav_ms, draws])

	print("PERF_TIMING_DONE")
	get_tree().quit()
