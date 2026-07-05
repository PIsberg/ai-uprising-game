extends Node
## Headless assertions for GraphicsSettings.apply_preset() and set_window_mode().
## Run: Godot --headless --path . res://tests/preset_probe.tscn
##
## Verifies the batch-applied preset matrix (quality / render_scale / the eight
## feature toggles) for PERFORMANCE / BALANCED / QUALITY / ULTRA, that presets
## NEVER touch hdr_output_enabled, and that set_window_mode() applies + persists
## without crashing under the headless display server.
##
## IMPORTANT: this test drives the real GraphicsSettings autoload, which
## persists every change straight to user://settings.cfg — that's the dev's
## real settings file. We snapshot its raw bytes before touching anything and
## rewrite them verbatim at the end (whether the test passes or fails), so a
## probe run never clobbers a real player's/dev's saved settings.
##
## Prints PASS/FAIL per assertion + a final RESULT line, exits non-zero on
## any failure.

var _failures := 0
const SETTINGS_PATH := "user://settings.cfg"

func _ready() -> void:
	var had_file := FileAccess.file_exists(SETTINGS_PATH)
	var backup_bytes := PackedByteArray()
	if had_file:
		var rf := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		backup_bytes = rf.get_buffer(rf.get_length())
		rf.close()

	_run_assertions()

	# ---- restore the dev's real settings, no matter what happened above ----
	if had_file:
		var wf := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		wf.store_buffer(backup_bytes)
		wf.close()
	else:
		var da := DirAccess.open("user://")
		if da and da.file_exists("settings.cfg"):
			da.remove("settings.cfg")
	# Reload the live singleton from the restored file so in-memory state
	# matches what's on disk again (best-effort cleanliness; this process is
	# about to quit anyway).
	GraphicsSettings._load_settings()

	print("=== %s ===" % ("ALL PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL"))
	get_tree().quit(0 if _failures == 0 else 1)

func _run_assertions() -> void:
	# ---- PERFORMANCE ----
	GraphicsSettings.set_hdr_output_enabled(true) # so we can prove presets don't touch it
	GraphicsSettings.apply_preset(GraphicsSettings.PRESET_PERFORMANCE)
	_assert_matrix("PERFORMANCE", GraphicsSettings.Quality.LOW, 0.67, true, false, false, false, false, false, false)
	_assert(GraphicsSettings.hdr_output_enabled == true, "PERFORMANCE leaves hdr_output_enabled untouched (still true)")
	GraphicsSettings.set_hdr_output_enabled(false) # restore per spec

	# ---- BALANCED ----
	GraphicsSettings.apply_preset(GraphicsSettings.PRESET_BALANCED)
	_assert_matrix("BALANCED", GraphicsSettings.Quality.MEDIUM, 0.85, true, false, true, true, false, false, false)

	# ---- QUALITY ----
	GraphicsSettings.apply_preset(GraphicsSettings.PRESET_QUALITY)
	_assert_matrix("QUALITY", GraphicsSettings.Quality.HIGH, 1.0, true, true, true, true, true, true, false)

	# ---- ULTRA ----
	GraphicsSettings.apply_preset(GraphicsSettings.PRESET_ULTRA)
	_assert_matrix("ULTRA", GraphicsSettings.Quality.ULTRA, 1.0, true, true, true, true, true, true, false)

	# ---- window mode: headless guard + persistence ----
	# If DisplayServer.get_name() == "headless" isn't actually guarded in
	# _apply_window_mode, this call would throw/crash on a headless display
	# server and the probe itself would never reach the print below.
	GraphicsSettings.set_window_mode(GraphicsSettings.WindowMode.WINDOWED)
	_assert(GraphicsSettings.window_mode == GraphicsSettings.WindowMode.WINDOWED,
		"set_window_mode(WINDOWED) didn't crash under headless and updated the live field")

	var cf := ConfigFile.new()
	var loaded_ok := cf.load(SETTINGS_PATH) == OK
	var persisted: int = int(cf.get_value("display", "window_mode", -1)) if loaded_ok else -1
	_assert(persisted == int(GraphicsSettings.WindowMode.WINDOWED),
		"window_mode persisted to settings.cfg (display/window_mode=%d)" % persisted)

## Asserts the full preset matrix in one shot; prints one PASS/FAIL per field
## instead of a single opaque line so a failure points straight at the field.
func _assert_matrix(label: String, quality: int, render_scale: float, gpu_particles: bool,
		volumetric: bool, triplanar: bool, puddles: bool, post_process: bool,
		area_lights: bool, dof: bool) -> void:
	_assert(GraphicsSettings.quality == quality, "%s: quality == %s" % [label, GraphicsSettings.LABELS[quality]])
	_assert(is_equal_approx(GraphicsSettings.render_scale, render_scale), "%s: render_scale == %.2f (got %.2f)" % [label, render_scale, GraphicsSettings.render_scale])
	_assert(GraphicsSettings.gpu_particles_enabled == gpu_particles, "%s: gpu_particles_enabled == %s" % [label, gpu_particles])
	_assert(GraphicsSettings.volumetric_noise_enabled == volumetric, "%s: volumetric_noise_enabled == %s" % [label, volumetric])
	_assert(GraphicsSettings.robot_triplanar_enabled == triplanar, "%s: robot_triplanar_enabled == %s" % [label, triplanar])
	_assert(GraphicsSettings.puddle_ripples_enabled == puddles, "%s: puddle_ripples_enabled == %s" % [label, puddles])
	_assert(GraphicsSettings.advanced_post_process_enabled == post_process, "%s: advanced_post_process_enabled == %s" % [label, post_process])
	_assert(GraphicsSettings.area_lights_enabled == area_lights, "%s: area_lights_enabled == %s" % [label, area_lights])
	_assert(GraphicsSettings.dof_enabled == dof, "%s: dof_enabled == %s" % [label, dof])

func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: %s" % msg)
	else:
		print("FAIL: %s" % msg)
		_failures += 1
