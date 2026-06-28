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
	"The AI learns how you fight — vary your weapons and angles to stay unpredictable.",
	"WARDEN elites can't be staggered. Dodge their attacks; don't try to trade.",
	"VOLATILE elites detonate on death — don't be standing next to one when it drops.",
	"Fall into lava or deep water and it cooks you. Stay on the walkways.",
	"Standing in lava burns you fast — it drains health every second you're in it. Keep to the dark walkways.",
	"Out of ammo mid-fight? Switch to another loaded weapon instead of reloading — the swap is faster and can be the difference between living and dying.",
	"Every gun has a role — check the Weapon Codex from the main menu.",
	"Hunt the marked high-value target to clear an assassination sector.",
]

var _spinner: Control
var _dots_lbl: Label
var _t: float = 0.0
var _started: bool = false
var _path: String = ""        ## scene being threaded-loaded
var _loading: bool = false    ## a threaded load is in flight
var _progress: float = 0.0    ## 0..1, smoothed, drives the ring + percent

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	# Paint a few frames so this screen is actually on-screen, THEN kick the
	# heavy load — its main-thread build will sit on THIS frame, not on grey.
	_go.call_deferred()

const BG_IMAGE := "res://assets/textures/ui/menu_background.png"

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.04, 0.06)
	add_child(bg)

	# Actual loading artwork behind the text — the menu key-art, dimmed so the
	# title/spinner stay readable. (Falls back to the flat colour if missing.)
	if ResourceLoader.exists(BG_IMAGE):
		var art := TextureRect.new()
		art.texture = load(BG_IMAGE)
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.modulate = Color(1, 1, 1, 0.45)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)
		# A dark scrim over the art so the centred text reads cleanly.
		var scrim := ColorRect.new()
		scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
		scrim.color = Color(0.02, 0.03, 0.05, 0.45)
		scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(scrim)

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
	if _loading:
		_poll_load()
	if _spinner:
		_spinner.queue_redraw()
	if _dots_lbl:
		# The ring shows the real fraction; the label shows the percent.
		_dots_lbl.text = "LOADING  %d%%" % int(clampf(_progress, 0.0, 1.0) * 100.0)

## Read threaded-load progress; swap to the scene once it's fully loaded.
func _poll_load() -> void:
	var prog: Array = []
	var status := ResourceLoader.load_threaded_get_status(_path, prog)
	if prog.size() > 0:
		# Ease toward the reported value so the ring fills smoothly, never backwards.
		_progress = maxf(_progress, lerpf(_progress, float(prog[0]), 0.35))
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			_loading = false
			_progress = 1.0
			var packed := ResourceLoader.load_threaded_get(_path) as PackedScene
			if packed:
				get_tree().change_scene_to_packed(packed)
			else:
				get_tree().change_scene_to_file(_path)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_loading = false
			get_tree().change_scene_to_file(_path) # last-ditch fallback

func _draw_spinner() -> void:
	var c := _spinner.size * 0.5
	var r := 26.0
	# Dim full ring + a bright arc filled to the real load fraction (from 12 o'clock).
	_spinner.draw_arc(c, r, 0, TAU, 64, Color(0.2, 0.3, 0.45), 4.0, true)
	var start := -PI * 0.5
	var sweep := clampf(_progress, 0.0, 1.0) * TAU
	if sweep > 0.001:
		_spinner.draw_arc(c, r, start, start + sweep, 64, Color(0.4, 0.75, 1.0), 5.0, true)
	# A small leading dot so it still reads as "alive" even at 0%.
	var head := start + sweep
	_spinner.draw_circle(c + Vector2(cos(head), sin(head)) * r, 3.5, Color(0.7, 0.9, 1.0))

func _go() -> void:
	if _started:
		return
	_started = true
	# A few frames so this screen is actually presented first.
	for i in 4:
		await get_tree().process_frame
	# Threaded load so the heavy scene + its asset deps load on a background thread
	# while we keep ticking the progress ring (a blocking change_scene couldn't
	# report progress). _poll_load() swaps in the scene when it's ready.
	_path = GameState.pending_scene
	if _path == "" or not ResourceLoader.exists(_path):
		get_tree().change_scene_to_file(_path)
		return
	if ResourceLoader.load_threaded_request(_path) == OK:
		_loading = true
	else:
		get_tree().change_scene_to_file(_path) # fallback if the request was refused
