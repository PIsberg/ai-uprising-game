extends Control
## End-of-campaign credits crawl: game title, dev credit, engine + CC0 asset
## attributions (summarised from CREDITS.md — keep the two in sync if either
## changes). Reached from victory_cutscene.gd after the closing broadcast.
## Scrolls bottom-to-top and returns to the main menu when it finishes or the
## player skips — skip is gated by a short grace period so a stray keypress
## carrying over from the transmission can't blow straight through this too.

const SKIP_GRACE := 1.5
const SCROLL_SPEED := 34.0 # px/sec
const MAIN_MENU := "res://scenes/ui/main_menu.tscn"

## {text, size, color?, gap (px of space after this line)}.
const LINES: Array = [
	{"text": "AI UPRISING", "size": 54, "color": Color(0.95, 0.96, 1.0), "gap": 40},
	{"text": "A game by Peter Isberg", "size": 22, "color": Color(0.75, 0.82, 0.95), "gap": 70},
	{"text": "CAMPAIGN COMPLETE", "size": 20, "color": Color(1.0, 0.6, 0.3), "gap": 60},
	{"text": "ENGINE", "size": 16, "color": Color(0.55, 0.62, 0.75), "gap": 8},
	{"text": "Godot Engine 4.7  —  godotengine.org", "size": 18, "gap": 50},
	{"text": "THIRD-PARTY ASSETS  (CC0 unless noted)", "size": 16, "color": Color(0.55, 0.62, 0.75), "gap": 8},
	{"text": "Quaternius (quaternius.com) — enemy robot models", "size": 18, "gap": 4},
	{"text": "Kenney (kenney.nl) — weapon models, suburb & car kits", "size": 18, "gap": 4},
	{"text": "ambientCG (ambientcg.com) — PBR surface textures", "size": 18, "gap": 4},
	{"text": "Poly Haven (polyhaven.com) — HDRI sky", "size": 18, "gap": 4},
	{"text": "Poly Pizza (poly.pizza) — model hosting", "size": 18, "gap": 4},
	{"text": "dook — data crystal & off-world drone models", "size": 18, "gap": 4},
	{"text": "Dann Beeson — \"Giant Robot\" finale boss model (CC-BY 3.0)", "size": 18, "gap": 4},
	{"text": "Matt McInerney — Orbitron font (SIL OFL 1.1), Google Fonts", "size": 18, "gap": 4},
	{"text": "Full attributions in CREDITS.md", "size": 14, "color": Color(0.5, 0.55, 0.65), "gap": 90},
	{"text": "THANK YOU FOR PLAYING", "size": 30, "color": Color(1.0, 0.85, 0.4), "gap": 220},
]

var _crawl: VBoxContainer
var _t: float = 0.0
var _done: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.016, 0.02)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var mask := Control.new()
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.clip_contents = true
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mask)

	_crawl = VBoxContainer.new()
	_crawl.alignment = BoxContainer.ALIGNMENT_BEGIN
	_crawl.add_theme_constant_override("separation", 4)
	_crawl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_crawl.anchor_left = 0.5
	_crawl.anchor_right = 0.5
	_crawl.offset_left = -360.0
	_crawl.offset_right = 360.0
	mask.add_child(_crawl)

	for entry in LINES:
		var lbl := Label.new()
		lbl.text = str(entry.get("text", ""))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", int(entry.get("size", 18)))
		lbl.add_theme_color_override("font_color", entry.get("color", Color(0.85, 0.88, 0.95)))
		lbl.add_theme_constant_override("outline_size", 6)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		_crawl.add_child(lbl)
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, float(entry.get("gap", 10)))
		_crawl.add_child(spacer)

	var hint := Label.new()
	hint.text = "Press any key to skip"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_top = -46.0
	hint.offset_bottom = -14.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75, 0.7))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)

	set_process(true)
	set_process_input(true)
	# Start just below the bottom edge — needs a frame for the crawl to report
	# its real (post-layout) size and for the viewport rect to be current.
	await get_tree().process_frame
	_crawl.position.y = get_viewport_rect().size.y

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_crawl.position.y -= SCROLL_SPEED * delta
	if _crawl.position.y + _crawl.size.y < -40.0:
		_finish()

func _input(event: InputEvent) -> void:
	if _done or _t < SKIP_GRACE:
		return
	if (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventJoypadButton and event.pressed):
		_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	get_tree().change_scene_to_file(MAIN_MENU)
