extends Control
## Shown for a beat before a heavy level scene loads. The procedural level build
## stalls the main thread inside the level's _ready (geometry, navmesh, GI), and
## Godot keeps displaying the LAST rendered frame until the new scene draws — so
## without this the player stares at a grey window. We paint a proper loading
## frame first, render it, THEN trigger the heavy change_scene: the build now
## freezes on this screen instead of on grey.
##
## GameState.pending_scene holds the real target (the level .tscn, or
## level_custom.tscn for .lvl data levels). Routed here by GameState.load_level.

const TIPS := [
	"Headshots drop most infantry units instantly.",
	"Dash (Q) has brief invincibility — time it through fire.",
	"Menders heal the whole pack. Kill them first.",
	"Flank Bulwark Brutes — their front shield eats everything.",
	"Reload behind cover; a dry mag gets you killed in the open.",
	"Heavy weapons stagger big units. Save them for the brutes.",
	"Skitters bunch up — splash and chain weapons shred them.",
	"Keep moving against snipers; the red beam marks the shot.",
]

var _spinner: Control
var _dots_lbl: Label
var _t: float = 0.0
var _started: bool = false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	# Paint a few frames so this screen is actually on-screen, THEN kick the
	# heavy load — its main-thread build will sit on THIS frame, not on grey.
	_go.call_deferred()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.04, 0.06)
	add_child(bg)

	# Centered block: level name, animated spinner, LOADING + dots, a tip.
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 22)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(box)

	var lid := GameState.level_id_from_path(GameState.current_level_path)
	var def := LevelDefs.get_def(lid)
	var lname: String = def.get("name", "")

	if lname != "":
		var kicker := Label.new()
		kicker.text = "ENTERING"
		kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kicker.add_theme_font_size_override("font_size", 18)
		kicker.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
		box.add_child(kicker)

		var title := Label.new()
		title.text = lname.to_upper()
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 44)
		title.add_theme_color_override("font_color", Color(1, 0.96, 0.9))
		box.add_child(title)

	_spinner = Control.new()
	_spinner.custom_minimum_size = Vector2(64, 64)
	_spinner.draw.connect(_draw_spinner)
	# center the spinner horizontally
	var center := CenterContainer.new()
	center.custom_minimum_size = Vector2(0, 72)
	center.add_child(_spinner)
	box.add_child(center)

	_dots_lbl = Label.new()
	_dots_lbl.text = "LOADING"
	_dots_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dots_lbl.add_theme_font_size_override("font_size", 22)
	_dots_lbl.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9))
	box.add_child(_dots_lbl)

	# Tactical tip, pinned near the bottom.
	var tip := Label.new()
	# Index varies by level so it isn't always the same tip (no RNG needed).
	tip.text = "TIP:  " + TIPS[abs(lid.hash()) % TIPS.size()]
	tip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tip.anchor_top = 1.0; tip.anchor_bottom = 1.0
	tip.offset_top = -110.0; tip.offset_bottom = -70.0
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 18)
	tip.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	add_child(tip)

func _process(delta: float) -> void:
	_t += delta
	if _spinner:
		_spinner.queue_redraw()
	if _dots_lbl:
		var n := int(_t * 3.0) % 4
		_dots_lbl.text = "LOADING" + ".".repeat(n)

func _draw_spinner() -> void:
	var c := _spinner.size * 0.5
	var r := 26.0
	# A bright arc chasing around a dim ring.
	_spinner.draw_arc(c, r, 0, TAU, 48, Color(0.2, 0.3, 0.45), 4.0, true)
	var a := _t * 4.0
	_spinner.draw_arc(c, r, a, a + TAU * 0.28, 24, Color(0.4, 0.75, 1.0), 5.0, true)

func _go() -> void:
	if _started:
		return
	_started = true
	# A few frames guarantees the screen has actually been presented before the
	# blocking build begins.
	for i in 4:
		await get_tree().process_frame
	get_tree().change_scene_to_file(GameState.pending_scene)
