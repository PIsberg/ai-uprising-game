extends Control
## Campaign opener as a motion-comic: the three panels of the intro page slide in
## one at a time (page-turn → reveal → hold) with animated FX layered over the
## art — glowing muzzle fire, enemy laser beams, pulsing red eyes / hologram
## glow — then we drop into level 1. Any key/click/button skips.
##
## The source art is one tall page (1696×2528) holding three stacked panels; we
## show each via an AtlasTexture region. FX are placed in NORMALISED panel coords
## (0..1 over the fitted image) so they track the art at any window size.

const COMIC := preload("res://assets/comics/intro_comic.png")

## Pixel regions of each panel in the source page (x, y, w, h). Tuned to the art.
const PANELS: Array = [
	Rect2(28, 24, 1640, 802),
	Rect2(28, 852, 1640, 802),
	Rect2(28, 1690, 1640, 812),
]
const PANEL_HOLD := 2.6  ## Seconds each panel lingers after flashing in.

const C_WARM := Color(1.0, 0.82, 0.45)   # ballistic muzzle fire
const C_BLUE := Color(0.5, 0.8, 1.0)     # the hero's energy weapon / holograms
const C_RED := Color(1.0, 0.22, 0.14)    # machine eyes / lasers

## FX per panel. kind: "muzzle" (fast bright flicker), "glow" (slow pulse),
## "laser" (a flickering beam a→b). Positions are normalised (0..1) within the panel.
const PANEL_FX: Array = [
	[ # Panel 1 — NEXUS POINT: hero pops a shot, the nexus tower + drones glow red
		{"kind": "muzzle", "u": 0.305, "v": 0.735, "size": 64, "color": C_BLUE},
		{"kind": "glow", "u": 0.628, "v": 0.165, "size": 96, "color": C_RED, "freq": 5.0},
		{"kind": "glow", "u": 0.60, "v": 0.135, "size": 60, "color": C_RED, "freq": 6.0},
		{"kind": "glow", "u": 0.628, "v": 0.40, "size": 54, "color": C_RED, "freq": 4.0},
		{"kind": "glow", "u": 0.47, "v": 0.10, "size": 22, "color": C_RED, "freq": 7.0},
		{"kind": "glow", "u": 0.80, "v": 0.13, "size": 22, "color": C_RED, "freq": 8.0},
	],
	[ # Panel 2 — OVERWHELMING FORCE: the big rifle blast + the mech firing back
		{"kind": "muzzle", "u": 0.455, "v": 0.455, "size": 150, "color": C_WARM},
		{"kind": "laser", "a": Vector2(0.285, 0.50), "b": Vector2(0.44, 0.47), "color": C_RED},
		{"kind": "glow", "u": 0.275, "v": 0.50, "size": 52, "color": C_RED, "freq": 9.0},
		{"kind": "glow", "u": 0.205, "v": 0.32, "size": 34, "color": C_RED, "freq": 6.0},
		{"kind": "glow", "u": 0.86, "v": 0.55, "size": 30, "color": C_RED, "freq": 7.0},
	],
	[ # Panel 3 — ADAPTIVE AI: holo displays, red scanner, robot eyes, hero shot
		{"kind": "glow", "u": 0.50, "v": 0.40, "size": 130, "color": C_BLUE, "freq": 3.0},
		{"kind": "glow", "u": 0.175, "v": 0.55, "size": 92, "color": C_RED, "freq": 6.0},
		{"kind": "muzzle", "u": 0.225, "v": 0.50, "size": 40, "color": C_WARM},
		{"kind": "glow", "u": 0.815, "v": 0.33, "size": 30, "color": C_RED, "freq": 8.0},
		{"kind": "glow", "u": 0.84, "v": 0.30, "size": 22, "color": C_RED, "freq": 9.0},
		{"kind": "glow", "u": 0.595, "v": 0.76, "size": 70, "color": C_BLUE, "freq": 4.0},
	],
]

var _atlas: AtlasTexture
var _panel_root: Control
var _img: TextureRect
var _fx_layer: Control
var _fade: ColorRect
var _add_mat: CanvasItemMaterial
var _fx: Array = []        # live FX node records for the current panel
var _t: float = 0.0
var _done := false

static var _flare_tex: Texture2D = null

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_add_mat = CanvasItemMaterial.new()
	_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Panel root is sized/positioned to the fitted image each panel; the image and
	# its FX live inside it so FX track the art exactly.
	_panel_root = Control.new()
	_panel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.modulate.a = 0.0
	add_child(_panel_root)

	_atlas = AtlasTexture.new()
	_atlas.atlas = COMIC
	_atlas.region = PANELS[0]
	_img = TextureRect.new()
	_img.texture = _atlas
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_SCALE
	_img.set_anchors_preset(Control.PRESET_FULL_RECT)
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(_img)

	_fx_layer = Control.new()
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(_fx_layer)

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
		_show_panel(i)
		# Page-turn: the new panel slides in from the right while fading up — no
		# white flash, no switch blip. Reads like turning to the next comic page.
		var target: Vector2 = _panel_root.position
		var slide := get_viewport_rect().size.x * 0.32
		_panel_root.position = target + Vector2(slide, 0.0)
		_panel_root.modulate.a = 0.0
		var rev := create_tween().set_parallel(true)
		rev.tween_property(_panel_root, "position", target, 0.5) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		rev.tween_property(_panel_root, "modulate:a", 1.0, 0.35) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await _wait(PANEL_HOLD)
	_finish()

## Lay out the panel image to fit the screen (aspect-preserved, centred) and build
## its FX in that fitted rect.
func _show_panel(i: int) -> void:
	_atlas.region = PANELS[i]
	var region: Rect2 = PANELS[i]
	var margin := Vector2(60, 30)
	var avail := get_viewport_rect().size - margin * 2.0
	var aspect := region.size.x / region.size.y
	var w := avail.x
	var h := w / aspect
	if h > avail.y:
		h = avail.y
		w = h * aspect
	_panel_root.position = margin + (avail - Vector2(w, h)) * 0.5
	_panel_root.size = Vector2(w, h)
	_build_fx(PANEL_FX[i], Vector2(w, h))

func _build_fx(specs: Array, panel_size: Vector2) -> void:
	for c in _fx_layer.get_children():
		c.queue_free()
	_fx.clear()
	# Scale FX sizes (authored against a ~1280px-wide panel) to the fitted width.
	var s := panel_size.x / 1280.0
	for spec in specs:
		match spec.get("kind", "glow"):
			"laser":
				_make_laser(
					Vector2(spec["a"]) * panel_size,
					Vector2(spec["b"]) * panel_size,
					spec["color"], s)
			_:
				_make_flare(
					Vector2(spec["u"], spec["v"]) * panel_size,
					float(spec["size"]) * s, spec["color"],
					spec["kind"] == "muzzle", float(spec.get("freq", 5.0)))

## A camera-flat additive glow sprite (muzzle flash / eye / hologram bloom).
func _make_flare(pos: Vector2, size: float, color: Color, muzzle: bool, freq: float) -> void:
	var tr := TextureRect.new()
	tr.texture = _flare_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.custom_minimum_size = Vector2(size, size)
	tr.size = Vector2(size, size)
	tr.pivot_offset = Vector2(size, size) * 0.5
	tr.position = pos - Vector2(size, size) * 0.5
	tr.modulate = color
	tr.material = _add_mat
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(tr)
	_fx.append({"node": tr, "muzzle": muzzle, "freq": freq, "phase": randf() * TAU,
		"base": Vector2(size, size) * 0.5})

## A flickering beam: a wide soft glow with a thin white-hot core, A→B.
func _make_laser(a: Vector2, b: Vector2, color: Color, s: float) -> void:
	var d := b - a
	var length := d.length()
	var ang := d.angle()
	var glow := ColorRect.new()
	glow.color = Color(color.r, color.g, color.b, 0.55)
	glow.size = Vector2(length, 12.0 * s)
	glow.pivot_offset = Vector2(0, 6.0 * s)
	glow.position = a
	glow.rotation = ang
	glow.material = _add_mat
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(glow)
	var core := ColorRect.new()
	core.color = Color(1.0, 0.6, 0.5, 0.95)
	core.size = Vector2(length, 3.5 * s)
	core.pivot_offset = Vector2(0, 1.75 * s)
	core.position = a
	core.rotation = ang
	core.material = _add_mat
	core.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.add_child(core)
	# A bright bloom where the beam is emitted.
	_make_flare(a, 44.0 * s, color, true, 11.0)
	_fx.append({"laser": true, "glow": glow, "core": core, "phase": randf() * TAU})

func _process(delta: float) -> void:
	if _fx.is_empty():
		return
	_t += delta
	for f in _fx:
		if f.has("laser"):
			var flick: float = 0.65 + 0.35 * sin(_t * 40.0 + f["phase"]) + 0.1 * sin(_t * 13.0)
			f["glow"].modulate.a = clampf(flick, 0.2, 1.0)
			f["core"].modulate.a = clampf(0.7 + 0.3 * sin(_t * 55.0 + f["phase"]), 0.3, 1.0)
			continue
		var node: TextureRect = f["node"]
		if not is_instance_valid(node):
			continue
		var freq: float = f["freq"]
		var k: float
		if f["muzzle"]:
			# Rapid, jittery — reads as live gunfire.
			k = 0.45 + 0.4 * absf(sin(_t * freq * 2.0 + f["phase"])) + randf() * 0.18
		else:
			# Slow breathing pulse for eyes / holograms.
			k = 0.7 + 0.3 * sin(_t * freq + f["phase"])
		node.modulate.a = clampf(k, 0.2, 1.3)
		var sc := 1.0 + (0.18 if f["muzzle"] else 0.07) * (k - 0.7)
		node.scale = Vector2(sc, sc)

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

## A soft radial glow (bright opaque centre → transparent edge), built once.
static func _flare_texture() -> Texture2D:
	if _flare_tex != null:
		return _flare_tex
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c := Vector2(sz * 0.5, sz * 0.5)
	for y in sz:
		for x in sz:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(c) / (sz * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_flare_tex = ImageTexture.create_from_image(img)
	return _flare_tex
