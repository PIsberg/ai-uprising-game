extends Node
## Bisects WHY level rendering is so much slower than the empty-scene baseline
## (110 fps): loads one level, measures fps normally, then flips off one
## environment feature at a time (SSAO/SSIL/SSR/volumetric fog/glow) and
## re-measures, to isolate which is actually responsible for the drop.
## Run: godot --path . --quit-after 4000 tools/perf_bisect.tscn

const LEVEL_ID := "gpt"
const WARMUP := 40
const MEASURE := 100

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DisplayServer.window_set_size(Vector2i(1280, 720))
	if GraphicsSettings:
		GraphicsSettings.quality = 2
		GraphicsSettings._apply_viewport()
	var lvl: Node = load("res://scenes/levels/level_%s.tscn" % LEVEL_ID).instantiate()
	add_child(lvl)
	for f in 90: # let it fully settle (navmesh bake, spawns, shader warmup)
		await get_tree().process_frame

	var wes := lvl.find_children("*", "WorldEnvironment", true, false)
	var we: WorldEnvironment = wes[0] if wes.size() > 0 else null
	var env := we.environment if we else null

	await _measure("baseline (all features as authored)")
	if env:
		var orig_ssao = env.ssao_enabled
		var orig_ssil = env.ssil_enabled
		var orig_ssr = env.ssr_enabled
		var orig_fog = env.volumetric_fog_enabled
		var orig_glow = env.glow_enabled

		env.ssao_enabled = false
		await _measure("SSAO off")
		env.ssao_enabled = orig_ssao

		env.ssil_enabled = false
		await _measure("SSIL off")
		env.ssil_enabled = orig_ssil

		env.ssr_enabled = false
		await _measure("SSR off")
		env.ssr_enabled = orig_ssr

		env.volumetric_fog_enabled = false
		await _measure("volumetric fog off")
		env.volumetric_fog_enabled = orig_fog

		env.glow_enabled = false
		await _measure("glow off")
		env.glow_enabled = orig_glow

		env.ssao_enabled = false
		env.ssil_enabled = false
		env.ssr_enabled = false
		env.volumetric_fog_enabled = false
		env.glow_enabled = false
		await _measure("ALL screen-space effects off")
	else:
		print("no WorldEnvironment found")

	# Try disabling shadows entirely (directional + all lights) as a coarse check.
	var lights := lvl.find_children("*", "Light3D", true, false)
	var shadow_states := []
	for l in lights:
		shadow_states.append((l as Light3D).shadow_enabled)
		(l as Light3D).shadow_enabled = false
	await _measure("all shadows off (%d lights)" % lights.size())
	for i in lights.size():
		(lights[i] as Light3D).shadow_enabled = shadow_states[i]

	print("PERF_BISECT_DONE")
	get_tree().quit()

func _measure(label: String) -> void:
	for f in WARMUP:
		await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	for f in MEASURE:
		await get_tree().process_frame
	var dt := (Time.get_ticks_usec() - t0) / 1000000.0
	print("BISECT %-38s fps=%6.1f" % [label, MEASURE / dt])
