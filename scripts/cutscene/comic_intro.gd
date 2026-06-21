extends Control
## Campaign opener as a motion-comic: the three panels of the intro page flash in
## one at a time (white pop → reveal → hold), then we drop into level 1. Replaces
## the old 3D story cutscene. Any key/click/button skips straight to the level.
##
## The source art is one tall page (1696×2528) holding three stacked panels; we
## show each via an AtlasTexture region so there's a single image asset.

const COMIC := preload("res://assets/comics/intro_comic.png")

## Pixel regions of each panel in the source page (x, y, w, h). Tuned to the art.
const PANELS: Array = [
	Rect2(28, 24, 1640, 802),
	Rect2(28, 852, 1640, 802),
	Rect2(28, 1690, 1640, 812),
]
const PANEL_HOLD := 2.2  ## Seconds each panel lingers after flashing in.

var _img: TextureRect
var _atlas: AtlasTexture
var _flash: ColorRect
var _fade: ColorRect
var _done := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_atlas = AtlasTexture.new()
	_atlas.atlas = COMIC
	_atlas.region = PANELS[0]
	_img = TextureRect.new()
	_img.texture = _atlas
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_img.set_anchors_preset(Control.PRESET_FULL_RECT)
	# A little breathing room so the panel doesn't kiss the screen edges.
	_img.offset_left = 60; _img.offset_top = 30
	_img.offset_right = -60; _img.offset_bottom = -30
	_img.modulate.a = 0.0
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_img)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

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
	add_child(hint)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1) # start black, fade up on the first panel
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	set_process_unhandled_input(true)
	_run.call_deferred()

func _run() -> void:
	var up := create_tween()
	up.tween_property(_fade, "color:a", 0.0, 0.5)
	await up.finished
	for i in PANELS.size():
		if _done:
			break
		_atlas.region = PANELS[i]
		_img.modulate.a = 0.0
		_flash_panel()
		var rev := create_tween()
		rev.tween_property(_img, "modulate:a", 1.0, 0.22)
		if has_node("/root/AudioBus"):
			AudioBus.play_synth_ui("broadcast_blip", -4.0, 0.8 + 0.2 * i)
		await _wait(PANEL_HOLD)
	_finish()

## A white impact pop that fades out — the "flash" of each panel snapping in.
func _flash_panel() -> void:
	_flash.color.a = 0.95
	var t := create_tween()
	t.tween_property(_flash, "color:a", 0.0, 0.38)

## Wait `sec` real seconds, returning early the instant the player skips.
func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec and not _done:
		await get_tree().process_frame
		t += get_process_delta_time()

func _finish() -> void:
	var down := create_tween()
	down.tween_property(_fade, "color:a", 1.0, 0.5)
	await down.finished
	GameState.load_level(GameState.CAMPAIGN[0], false)

func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if (event is InputEventKey and event.pressed) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventJoypadButton and event.pressed):
		_done = true # _run sees this, breaks its hold, and finishes once
