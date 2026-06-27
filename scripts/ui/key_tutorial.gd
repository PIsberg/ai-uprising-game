class_name KeyTutorial
extends Control
## First-level interactive controls overlay.
##
## Shows a translucent list of every control and what it does, pinned to the
## left so it never covers the crosshair or the bottom HUD. The moment the
## player actually performs an action (presses its key/button, or moves the
## mouse to look), that row flashes green and fades away — so the list teaches
## by doing and clears itself as the player tries each control. When the last
## row is gone (or a grace timer elapses) the whole overlay removes itself.
##
## Built entirely in code and added as a child of the HUD by hud.gd on the
## first campaign level only — no scene file or editor wiring needed.

## How long leftover hints linger before they auto-fade, so the list can't
## clutter the screen for the whole level if the player ignores some keys.
const EXPIRE_SECONDS := 40.0

## One teachable control. `actions` are InputMap action names; pressing any of
## them clears the row. `mouse_look` rows clear on a real mouse movement instead.
const ENTRIES := [
	{"cap": "W A S D", "desc": "Move", "actions": ["move_forward", "move_back", "move_left", "move_right"]},
	{"cap": "Mouse", "desc": "Look around", "mouse_look": true},
	{"cap": "L-Click", "desc": "Fire weapon", "actions": ["fire"]},
	{"cap": "R-Click", "desc": "Aim down sight", "actions": ["aim"]},
	{"cap": "Space", "desc": "Jump", "actions": ["jump"]},
	{"cap": "Shift", "desc": "Sprint", "actions": ["sprint"]},
	{"cap": "Ctrl", "desc": "Crouch", "actions": ["crouch"]},
	{"cap": "Q", "desc": "Dash", "actions": ["dash"]},
	{"cap": "R", "desc": "Reload", "actions": ["reload"]},
	{"cap": "E", "desc": "Interact / pick up", "actions": ["interact"]},
	{"cap": "G", "desc": "Throw grenade", "actions": ["grenade"]},
	{"cap": "H", "desc": "Cycle grenade type", "actions": ["grenade_cycle"]},
	{"cap": "1-4 / Wheel", "desc": "Switch weapon",
		"actions": ["weapon_1", "weapon_2", "weapon_3", "weapon_4", "weapon_next", "weapon_prev"]},
	{"cap": "Esc", "desc": "Pause", "actions": ["pause"]},
]

var _rows: Array[Dictionary] = []
var _mouse_moved := false
var _expire := EXPIRE_SECONDS
var _box: VBoxContainer
var _finished := false

func _ready() -> void:
	# Run while playing but never block clicks — purely an overlay.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()

func _build() -> void:
	# Left-of-centre column so it dodges the crosshair, objective row and the
	# bottom-left/right HUD blocks.
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	holder.offset_left = 28
	holder.offset_right = 470
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.08, 0.55)
	style.set_corner_radius_all(8)
	style.set_border_width_all(1)
	style.border_color = Color(0.4, 0.8, 1.0, 0.35)
	style.content_margin_left = 16
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	holder.add_child(panel)

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 7)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_box)

	var title := Label.new()
	title.text = "CONTROLS"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 5)
	_box.add_child(title)

	var hint := Label.new()
	hint.text = "try each one — it clears as you go"
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(1, 1, 1, 0.6)
	_box.add_child(hint)

	var sep := HSeparator.new()
	_box.add_child(sep)

	for e in ENTRIES:
		_add_row(e)

	# Soft fade-in so it doesn't pop in hard at level start.
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.6)

func _add_row(entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Key "cap": a bordered chip showing the key/button.
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.12, 0.15, 0.2, 0.85)
	cs.set_corner_radius_all(5)
	cs.set_border_width_all(1)
	cs.border_color = Color(0.7, 0.8, 0.95, 0.6)
	cs.content_margin_left = 9
	cs.content_margin_right = 9
	cs.content_margin_top = 3
	cs.content_margin_bottom = 3
	cap.add_theme_stylebox_override("panel", cs)
	var cap_lbl := Label.new()
	cap_lbl.text = str(entry["cap"])
	cap_lbl.add_theme_font_size_override("font_size", 15)
	cap_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	cap_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap_lbl.custom_minimum_size = Vector2(118, 0)
	cap.add_child(cap_lbl)
	row.add_child(cap)

	var desc := Label.new()
	desc.text = str(entry["desc"])
	desc.add_theme_font_size_override("font_size", 16)
	desc.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	desc.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	desc.add_theme_constant_override("outline_size", 3)
	desc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(desc)

	_box.add_child(row)
	_rows.append({
		"row": row,
		"actions": entry.get("actions", []),
		"mouse_look": entry.get("mouse_look", false),
		"cap_style": cs,
		"done": false,
	})

func _input(event: InputEvent) -> void:
	# A real look movement (mouse is captured during play) clears the look row.
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 6.0:
		_mouse_moved = true

func _process(delta: float) -> void:
	if _finished:
		return
	var any_left := false
	for r in _rows:
		if r["done"]:
			continue
		var hit := false
		if r["mouse_look"] and _mouse_moved:
			hit = true
		else:
			for a in r["actions"]:
				if InputMap.has_action(a) and Input.is_action_just_pressed(a):
					hit = true
					break
		if hit:
			_dismiss(r)
		else:
			any_left = true
	_mouse_moved = false

	# Grace timer: once it elapses, sweep away whatever the player left untouched.
	_expire -= delta
	if _expire <= 0.0 and any_left:
		for r in _rows:
			if not r["done"]:
				_dismiss(r)
		any_left = false

	if not any_left:
		_finish()

## Flash the cleared row green, then collapse + fade it out and free it.
func _dismiss(r: Dictionary) -> void:
	if r["done"]:
		return
	r["done"] = true
	var row: HBoxContainer = r["row"]
	var cs: StyleBoxFlat = r["cap_style"]
	cs.bg_color = Color(0.2, 0.7, 0.3, 0.9)
	cs.border_color = Color(0.5, 1.0, 0.6, 0.95)
	AudioBus.play_synth_ui("broadcast_blip", -12.0, 1.6)
	row.modulate = Color(0.6, 1.0, 0.7)
	var t := row.create_tween()
	t.tween_interval(0.12)
	t.tween_property(row, "modulate:a", 0.0, 0.35)
	t.parallel().tween_property(row, "custom_minimum_size:y", 0.0, 0.35)
	t.tween_callback(row.queue_free)

func _finish() -> void:
	if _finished:
		return
	_finished = true
	var t := create_tween()
	t.tween_interval(0.3)
	t.tween_property(self, "modulate:a", 0.0, 0.5)
	t.tween_callback(queue_free)
