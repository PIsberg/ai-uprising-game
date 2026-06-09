class_name CutscenePlayer
extends Node3D
## Reusable, data-driven cinematic cutscene runner. Subclasses build the 3D set
## (`_build_set`) and supply a shot list (`_shots`); this base handles the
## cinematic camera with depth-of-field, a richer-than-gameplay environment
## (heavy bloom, volumetric god-rays, filmic grade), letterbox bars, subtitles,
## fades, a subtle handheld sway, and skip. Emits `finished` (and calls
## `_on_finished`) when the timeline ends or the player skips.
##
## A "shot" is a Dictionary:
##   {dur, from_pos, from_look, to_pos, to_look, text?, fade_in?, fade_out?}

signal finished

const POST_SHADER := preload("res://shaders/post_process.gdshader")

var camera: Camera3D
var _subtitle: Label
var _title: Label
var _fade: ColorRect
var _flash: ColorRect
var _post: ColorRect

var _active: Dictionary = {}
var _shot_time: float = 0.0
var _sway_t: float = 0.0
var _shake: float = 0.0
var _skipped: bool = false
var _running: bool = false

func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_overlay()
	_build_set()
	set_process_unhandled_input(true)
	_play.call_deferred()

# ---------- overridable by a specific cutscene ----------

## Spawn the 3D set (ground, actors, lights). Override in the cutscene script.
func _build_set() -> void:
	pass

## Return the ordered list of shots. Override in the cutscene script.
func _shots() -> Array:
	return []

## Called after the timeline finishes (or is skipped). Default: free the scene.
func _on_finished() -> void:
	pass

# ---------- cinematic rig ----------

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.016, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.34, 0.5)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_white = 8.0
	# Heavy, filmic bloom — emissives bloom hard for a cinematic look.
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.25
	env.glow_hdr_threshold = 0.9
	env.set("glow_levels/3", 1.0)
	env.set("glow_levels/4", 0.6)
	env.set("glow_levels/5", 0.3)
	# Volumetric fog for god-rays / atmosphere (cutscenes can afford it).
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.03
	env.volumetric_fog_albedo = Color(0.5, 0.55, 0.7)
	env.volumetric_fog_length = 120.0
	env.volumetric_fog_gi_inject = 0.4
	env.fog_enabled = true
	env.fog_light_color = Color(0.3, 0.35, 0.5)
	env.fog_density = 0.02
	# Filmic grade: cool shadows, lifted contrast & saturation.
	env.adjustment_enabled = true
	env.adjustment_brightness = 0.98
	env.adjustment_contrast = 1.16
	env.adjustment_saturation = 1.14
	we.environment = env
	add_child(we)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 38.0 # longer lens = compressed, cinematic
	# Depth-of-field so the subject pops against a soft background.
	var attr := CameraAttributesPractical.new()
	attr.dof_blur_far_enabled = true
	attr.dof_blur_far_distance = 14.0
	attr.dof_blur_far_transition = 8.0
	attr.dof_blur_near_enabled = true
	attr.dof_blur_near_distance = 1.2
	attr.dof_blur_near_transition = 1.0
	attr.dof_blur_amount = 0.12
	camera.attributes = attr
	add_child(camera)

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	# Film grain / vignette / aberration via the shared post shader.
	_post = ColorRect.new()
	_post.set_anchors_preset(Control.PRESET_FULL_RECT)
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = POST_SHADER
	mat.set_shader_parameter("vignette_strength", 0.6)
	mat.set_shader_parameter("grain_amount", 0.05)
	mat.set_shader_parameter("aberration", 1.6)
	_post.material = mat
	layer.add_child(_post)

	# Letterbox bars (2.39:1 cinema framing).
	var bar_h := 0.13
	var top := ColorRect.new()
	top.color = Color.BLACK
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.anchor_right = 1.0
	top.offset_bottom = 0.0
	top.anchor_bottom = bar_h
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(top)
	var bot := ColorRect.new()
	bot.color = Color.BLACK
	bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot.anchor_top = 1.0 - bar_h
	bot.anchor_bottom = 1.0
	bot.anchor_right = 1.0
	bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bot)

	# Subtitle, sitting just above the lower bar.
	_subtitle = Label.new()
	_subtitle.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_subtitle.anchor_top = 0.80
	_subtitle.anchor_bottom = 0.87
	_subtitle.anchor_right = 1.0
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override("font_size", 26)
	_subtitle.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	_subtitle.add_theme_constant_override("outline_size", 8)
	_subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_subtitle)

	# A "Skip ▸" hint, top-right.
	var hint := Label.new()
	hint.text = "Skip  ▸"
	hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint.anchor_left = 1.0
	hint.anchor_right = 1.0
	hint.offset_left = -150.0
	hint.offset_top = 18.0
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 0.6))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hint)

	# Big title card (hidden until a shot supplies `title`).
	_title = Label.new()
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.anchor_right = 1.0
	_title.anchor_bottom = 1.0
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 92)
	_title.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	_title.add_theme_constant_override("outline_size", 14)
	_title.add_theme_color_override("font_outline_color", Color(0.6, 0.05, 0.03, 1.0))
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.modulate.a = 0.0
	layer.add_child(_title)

	# Full-screen fade (starts black, fades up on the first shot).
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)

	# White impact flash, on top of everything.
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash)

## A bright screen flash that fades out — call from a shot action for an impact.
func screen_flash(strength: float = 0.9) -> void:
	if _flash == null:
		return
	_flash.color.a = clampf(strength, 0.0, 1.0)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.45)

## Kick the camera with shake (decays in _process). Call from a shot action.
func shake_camera(amount: float) -> void:
	_shake = maxf(_shake, amount)

# ---------- playback ----------

func _play() -> void:
	_running = true
	var shots := _shots()
	for shot in shots:
		if _skipped:
			break
		_active = shot
		_shot_time = 0.0
		_subtitle.text = shot.get("text", "")
		# Title card (big), fading in over the subtitle slot.
		if shot.has("title"):
			_title.text = shot["title"]
			var tt := create_tween()
			tt.tween_property(_title, "modulate:a", 1.0, 0.6)
		else:
			_title.modulate.a = 0.0
		# Snap the camera to the shot start so _process can interpolate.
		_apply_camera(0.0)
		if shot.get("fade_in", false):
			_tween_fade(0.0, 0.8)
		if shot.get("flash", false):
			screen_flash(0.95)
		if shot.get("shake", 0.0) > 0.0:
			shake_camera(shot["shake"])
		# Choreography: a shot can trigger an action (move actors, fire, ignite…).
		if shot.has("action"):
			var act: Callable = shot["action"]
			act.call()
		var dur: float = shot.get("dur", 3.0)
		while _shot_time < dur and not _skipped:
			await get_tree().process_frame
		if shot.get("fade_out", false) and not _skipped:
			_tween_fade(1.0, 0.8)
			await get_tree().create_timer(0.8, true).timeout
	_active = {}
	_subtitle.text = ""
	# Always finish on black.
	_tween_fade(1.0, 0.5)
	await get_tree().create_timer(0.55, true).timeout
	_running = false
	finished.emit()
	_on_finished()

func _tween_fade(to_a: float, dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", to_a, dur)

func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.2)
	if _active.is_empty():
		return
	_shot_time += delta
	_sway_t += delta
	var dur: float = _active.get("dur", 3.0)
	_apply_camera(clampf(_shot_time / dur, 0.0, 1.0))

func _apply_camera(raw: float) -> void:
	if camera == null or _active.is_empty():
		return
	var e := ease(raw, -1.8) # smooth ease-in-out for a dolly feel
	var fp: Vector3 = _active.get("from_pos", Vector3.ZERO)
	var tp: Vector3 = _active.get("to_pos", fp)
	var fl: Vector3 = _active.get("from_look", Vector3.FORWARD)
	var tl: Vector3 = _active.get("to_look", fl)
	# Subtle handheld sway so static shots still breathe, plus impact shake.
	var sway := Vector3(sin(_sway_t * 0.7) * 0.03, cos(_sway_t * 0.9) * 0.025, 0.0)
	if _shake > 0.0:
		sway += Vector3(randf() - 0.5, randf() - 0.5, 0.0) * _shake * 0.5
	camera.global_position = fp.lerp(tp, e) + sway
	var look := fl.lerp(tl, e)
	if camera.global_position.distance_to(look) > 0.05:
		camera.look_at(look, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if not _running or _skipped:
		return
	if (event is InputEventKey and event.pressed) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventJoypadButton and event.pressed):
		_skipped = true
