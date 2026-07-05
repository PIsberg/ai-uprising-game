extends Node
## Isolates the frame cost of each screen-space effect / AA / resolution at the
## REAL gameplay resolution (fullscreen, native scale), on a heavy interior
## level at HIGH tier. Each effect is toggled off alone, measured, restored —
## so every line is that one effect's cost against the same baseline.
## Run windowed:  godot --path . --quit-after 4000 res://tools/perf_fx_isolate.tscn

const LEVEL_ID := "gpt"
const WARM := 45
const M := 60

var _env: Environment
var _vp: Viewport

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	GraphicsSettings.quality = GraphicsSettings.Quality.HIGH
	GraphicsSettings._apply_viewport()
	var lvl: Node = load("res://scenes/levels/level_%s.tscn" % LEVEL_ID).instantiate()
	add_child(lvl)
	for f in 90:
		await get_tree().process_frame
	_vp = get_viewport()
	var wes := lvl.find_children("*", "WorldEnvironment", true, false)
	if wes.is_empty():
		push_error("no WorldEnvironment found")
		get_tree().quit()
		return
	_env = (wes[0] as WorldEnvironment).environment
	print("FX window=%s scale=%.2f" % [DisplayServer.window_get_size(), _vp.scaling_3d_scale])

	await _m("baseline HIGH")

	_env.ssil_enabled = false
	await _m("ssil OFF")
	_env.ssil_enabled = true

	_env.ssao_enabled = false
	await _m("ssao OFF")
	_env.ssao_enabled = true

	_env.ssr_enabled = false
	await _m("ssr OFF")
	_env.ssr_enabled = true

	_env.glow_enabled = false
	await _m("glow OFF")
	_env.glow_enabled = true

	var had_fog := _env.volumetric_fog_enabled
	_env.volumetric_fog_enabled = false
	await _m("volfog OFF")
	_env.volumetric_fog_enabled = had_fog

	_vp.msaa_3d = Viewport.MSAA_DISABLED
	await _m("msaa OFF")
	_vp.msaa_3d = Viewport.MSAA_2X

	_vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	_vp.scaling_3d_scale = 0.77
	await _m("render scale 0.77 FSR2")
	_vp.scaling_3d_scale = 0.5
	await _m("render scale 0.50 FSR2")
	_vp.scaling_3d_scale = 1.0
	_vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR

	# Candidate cheaper-HIGH: SSIL off + SSAO+SSR kept.
	_env.ssil_enabled = false
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	await _m("candidate: HIGH -ssil -msaa")

	print("FX_ISOLATE_DONE")
	get_tree().quit()

func _m(label: String) -> void:
	for i in WARM:
		await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	for i in M:
		await get_tree().process_frame
	var dt := (Time.get_ticks_usec() - t0) / 1000000.0
	print("FX %-28s fps=%6.1f  ms=%6.1f" % [label, M / dt, 1000.0 * dt / M])
