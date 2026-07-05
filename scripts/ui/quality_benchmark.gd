class_name QualityBenchmark
extends Node
## First-run quality auto-benchmark. Heuristics based on GPU name/vendor lie
## constantly (integrated vs discrete naming is a minefield, driver strings
## vary by OS) — a short measured render burn is honest about what THIS
## machine can actually push, so this class builds a representative offscreen
## scene, renders it for a couple of seconds, and reports back which quality
## tier the measured frame cost clears.
##
## Runs entirely inside an offscreen SubViewport (own_world_3d) that is never
## attached to anything visible, so it doesn't disturb whatever's on screen
## behind it (the main menu keeps rendering/responding to input normally).
##
## Usage: add as a child anywhere, connect `finished`, done. Frees itself.
signal finished(tier: int)

const VIEWPORT_SIZE := Vector2i(1152, 648)
## The scene's first draws compile Vulkan pipelines (shadow/SSAO/SSR/glow
## variants) — that one-time cost must burn out during warmup or it lands
## inside the measurement window and the benchmark under-tiers every fresh
## install (which is exactly when it runs).
const WARMUP_FRAMES := 25
const MEASURE_FRAMES := 40
const BOX_GRID := 12 # 12x10 = 120 boxes
const BOX_ROWS := 10

## Frame-cost thresholds (avg ms/frame over MEASURE_FRAMES). This is a coarse
## proxy, not a lab benchmark: 720p-ish internal res with the full effects
## stack (SSAO/SSR/glow/shadowed sun + 8 omnis/120 boxes) stands in for
## roughly what a busy combat arena costs at native res. Deliberately biased
## toward the SAFER (lower) tier on a boundary result — a tier is only
## awarded once the average clearly CLEARS its threshold, not merely nears it.
const ULTRA_MS := 4.0
const HIGH_MS := 8.0
const MEDIUM_MS := 16.0

## Exposed for the verification probe; not meant to be read by game code.
var avg_ms: float = -1.0

func _ready() -> void:
	# Dummy renderer under --headless never does real raster work — any timing
	# from it is meaningless noise, so just hand back the pre-benchmark
	# default (HIGH) and get out immediately without building anything.
	if DisplayServer.get_name() == "headless":
		_finish(GraphicsSettings.Quality.HIGH)
		return
	_run.call_deferred()

func _run() -> void:
	# vsync and an fps cap both clamp the deltas we're trying to measure —
	# save the current settings and restore them once we're done timing.
	var prev_vsync := DisplayServer.window_get_vsync_mode()
	var prev_max_fps := Engine.max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var viewport := _build_scene()
	add_child(viewport)

	for i in WARMUP_FRAMES:
		await get_tree().process_frame

	var t0 := Time.get_ticks_usec()
	for i in MEASURE_FRAMES:
		await get_tree().process_frame
	var elapsed_ms := (Time.get_ticks_usec() - t0) / 1000.0
	avg_ms = elapsed_ms / float(MEASURE_FRAMES)

	DisplayServer.window_set_vsync_mode(prev_vsync)
	Engine.max_fps = prev_max_fps

	var tier: int
	if avg_ms < ULTRA_MS:
		tier = GraphicsSettings.Quality.ULTRA
	elif avg_ms < HIGH_MS:
		tier = GraphicsSettings.Quality.HIGH
	elif avg_ms < MEDIUM_MS:
		tier = GraphicsSettings.Quality.MEDIUM
	else:
		tier = GraphicsSettings.Quality.LOW
	_finish(tier)

## Builds the offscreen representative-load scene: a shadowed sun + 8 point
## lights + a floor + 120 shared-mesh boxes behind full-fat screen-space
## effects, all inside its own SubViewport world so none of it is visible
## anywhere on screen.
func _build_scene() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.2, 0.25)
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.glow_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	viewport.add_child(sun)

	# ~8 shadowless point lights scattered over the grid — cheap per-light but
	# the count exercises the forward-clustered light budget.
	for i in 8:
		var omni := OmniLight3D.new()
		omni.shadow_enabled = false
		omni.omni_range = 12.0
		omni.light_energy = 1.5
		omni.position = Vector3(
			(randf() - 0.5) * float(BOX_GRID) * 2.0,
			3.0,
			(randf() - 0.5) * float(BOX_ROWS) * 2.0)
		viewport.add_child(omni)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(float(BOX_GRID) * 2.5, float(BOX_ROWS) * 2.5)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.3, 0.3, 0.32)
	floor_mat.metallic = 0.1
	floor_mat.roughness = 0.8
	floor_mesh.material = floor_mat
	var floor_inst := MeshInstance3D.new()
	floor_inst.mesh = floor_mesh
	viewport.add_child(floor_inst)

	# One shared BoxMesh + material for all ~120 instances: the cost being
	# measured is raster/lighting/post-process work, not unique-mesh overhead,
	# so every MeshInstance3D below points at the same resource.
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.0, 1.0, 1.0)
	var box_mat := StandardMaterial3D.new()
	box_mat.metallic = 0.4
	box_mat.roughness = 0.5
	box_mesh.material = box_mat

	for row in BOX_ROWS:
		for col in BOX_GRID:
			var box := MeshInstance3D.new()
			box.mesh = box_mesh
			box.position = Vector3(
				(col - float(BOX_GRID) / 2.0) * 2.0,
				0.5,
				(row - float(BOX_ROWS) / 2.0) * 2.0)
			viewport.add_child(box)

	var cam := Camera3D.new()
	var cam_pos := Vector3(0, 6, float(BOX_ROWS) * 1.5 + 6.0)
	# look_at_from_position (not position + look_at): the node isn't inside
	# the tree yet at this point, and look_at() requires a live global
	# transform to work from.
	cam.look_at_from_position(cam_pos, Vector3.ZERO, Vector3.UP)
	cam.current = true
	viewport.add_child(cam)

	return viewport

func _finish(tier: int) -> void:
	finished.emit(tier)
	queue_free()
