extends Node
## Does each graphics tier cost what it should? Builds a level per tier (LOW,
## MEDIUM, HIGH, ULTRA; the builder reads the tier at load, so each pass is a
## fresh build), pins render scale to 1.0 so only the tier differs, warms up,
## then prints the viewport's measured GPU and CPU render time with draw calls
## and primitives. Settings are changed in memory only, never saved. Windowed
## (render timings need a real GPU); it measures at the player's own window
## size, which it prints:
##   godot --path . tools/perf_tiers.tscn [-- levels=01,titan,neon tiers=0,1,2,3 frames=180]
##
## Ablation: `ablate=msaa,ssil,shadow,ssao,fog,ssr` runs the base tier (ULTRA,
## or `tier=N`) once as is and once per knob with only that knob turned down
## (msaa/ssil/shadow/ssao to HIGH's value, fog/ssr off; `msaa0`/`msaa2`/`msaa4`
## force an MSAA level). Build-time cost (shadowed-light budget, decor density)
## is whatever no knob explains.
##
## Reading GPU numbers from a laptop (docs/PERF_NOTES.md, "Graphics tiers"):
##   * run ONE configuration per process and take the median of repeats: an
##     earlier build's allocator blocks can leave the process over its VRAM
##     budget, paging memory to shared system RAM (#156: HIGH 118-134 ms
##     first, 222-239 ms after ULTRA);
##   * `burn=S` renders the first level for S seconds before measuring, since
##     the first ~30 s run ~40% faster than the throttled steady state;
##     `burn_scale=X` renders that burn at render scale X;
##   * the `vram_mb` column is Godot's allocated video memory. It cannot show
##     the spill above; the process's "GPU Process Memory" counters can.
##   * `repeat=N` repeats the run list in one process (quick look only).
## Each run frees everything it added under this node and root, or the next
## run would be measured with the last level's FX, pickups and enemies.

const TIER_NAMES := ["LOW", "MEDIUM", "HIGH", "ULTRA"]
var _levels: PackedStringArray = ["01", "titan", "neon"]
var _warmup := 90
var _frames := 180
var _ablate: PackedStringArray = []
var _repeat := 1
var _burn := 0.0
var _burn_scale := 1.0 ## render scale during the burn only (burn_scale=0.5 keeps an ULTRA burn under a 4 GB card's VRAM budget, #156)
var _base_tier := 3
var _tiers: Array = [0, 1, 2, 3]

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("levels="):
			_levels = a.trim_prefix("levels=").split(",")
		elif a.begins_with("frames="):
			_frames = int(a.trim_prefix("frames="))
		elif a.begins_with("ablate="):
			_ablate = a.trim_prefix("ablate=").split(",")
		elif a.begins_with("tiers="):
			_tiers = Array(a.trim_prefix("tiers=").split(",")).map(func(s): return clampi(int(s), 0, 3))
		elif a.begins_with("tier="):
			_base_tier = clampi(int(a.trim_prefix("tier=")), 0, 3)
		elif a.begins_with("burn_scale="):
			_burn_scale = clampf(float(a.trim_prefix("burn_scale=")), 0.25, 1.0)
		elif a.begins_with("burn="):
			_burn = float(a.trim_prefix("burn="))
		elif a.begins_with("repeat="):
			_repeat = maxi(1, int(a.trim_prefix("repeat=")))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	# The window mode from settings.cfg (often fullscreen) is applied deferred
	# at boot and wins over any size set here, so measure at whatever the
	# player's own window is and print it: 3D renders at the window size.
	await get_tree().process_frame
	print("window %s, render scale pinned to 1.0" % DisplayServer.window_get_size())
	await _run()
	get_tree().quit()

func _run() -> void:
	var gs := GraphicsSettings
	var saved_q: int = int(gs.quality)
	var saved_rs: float = gs.render_scale
	gs.render_scale = 1.0
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	print("GPU: %s" % gs.gpu_summary())
	if _burn > 0.0:
		gs.quality = _base_tier
		gs.render_scale = _burn_scale
		gs._apply_viewport()
		var keep := {}
		for n in get_children() + get_tree().root.get_children():
			keep[n] = true
		add_child(load("res://scenes/levels/level_%s.tscn" % _levels[0]).instantiate())
		var until := Time.get_ticks_msec() + int(_burn * 1000.0)
		while Time.get_ticks_msec() < until:
			await get_tree().process_frame
		print("burn done at t=%d, vram %d MB" % [Time.get_unix_time_from_system(), _vram_mb()])
		for n in get_children() + get_tree().root.get_children():
			if not keep.has(n):
				n.queue_free()
		gs.render_scale = 1.0
		await get_tree().process_frame
	print("level   tier     gpu_ms  cpu_ms  draws   prims  vram_mb  t")
	var runs: Array = _tiers.duplicate()
	if not _ablate.is_empty():
		runs = ["=" + TIER_NAMES[_base_tier]]
		for k in _ablate:
			runs.append("-" + k)
	var one := runs.duplicate()
	for i in _repeat - 1:
		runs.append_array(one)
	for id in _levels:
		for run in runs:
			var t: int = run if run is int else _base_tier
			# Levels spawn FX, pickups and enemies into current_scene (this
			# node) and some into root, outside `holder`. Anything left from
			# the previous run would be measured as part of this one: remember
			# what exists now and free everything new afterwards.
			var before := {}
			for n in get_children() + get_tree().root.get_children():
				before[n] = true
			gs.quality = t
			gs._apply_viewport()
			var holder := Node3D.new()
			add_child(holder)
			holder.add_child(load("res://scenes/levels/level_%s.tscn" % id).instantiate())
			if run is String and String(run).begins_with("-"):
				_drop_to_high(String(run).substr(1), holder)
			for f in _warmup:
				await get_tree().process_frame
			var gpu := 0.0
			var cpu := 0.0
			for f in _frames:
				await RenderingServer.frame_post_draw
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
				cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
			var rs := RenderingServer
			var label: String = TIER_NAMES[t] if run is int else String(run)
			print("%-7s %-7s %7.2f %7.2f %6d %8d %8d  %d" % [id, label, gpu / _frames, cpu / _frames,
				rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
				_vram_mb(), Time.get_unix_time_from_system()])
			for n in get_children() + get_tree().root.get_children():
				if not before.has(n):
					n.queue_free()
			await get_tree().process_frame
			await get_tree().process_frame
	gs.quality = saved_q
	gs.render_scale = saved_rs
	gs._apply_viewport()

## Video memory Godot has allocated (textures + buffers + render targets), MB.
## The OS may place part of it in shared system memory; compare with the
## process's "GPU Process Memory" counters (docs/PERF_NOTES.md).
func _vram_mb() -> int:
	return int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / (1024 * 1024))

## One ULTRA knob back to HIGH's value (GraphicsSettings._apply_viewport,
## _apply_shadow_quality, _apply_ss_effect_quality, apply_to_environment).
func _drop_to_high(knob: String, holder: Node) -> void:
	match knob:
		"msaa", "msaa2":
			get_viewport().msaa_3d = Viewport.MSAA_2X
		"fog":
			for we in holder.find_children("*", "WorldEnvironment", true, false):
				(we as WorldEnvironment).environment.volumetric_fog_enabled = false
		"ssr":
			for we in holder.find_children("*", "WorldEnvironment", true, false):
				(we as WorldEnvironment).environment.ssr_enabled = false
		"msaa0":
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		"msaa4":
			get_viewport().msaa_3d = Viewport.MSAA_4X
		"ssil":
			for we in holder.find_children("*", "WorldEnvironment", true, false):
				(we as WorldEnvironment).environment.ssil_enabled = false
		"shadow":
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
			RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			get_viewport().positional_shadow_atlas_size = 4096
		"ssao":
			RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 50.0, 300.0)
			RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_MEDIUM, true, 0.5, 4, 50.0, 300.0)
		_:
			push_error("perf_tiers: unknown ablate knob '%s'" % knob)
