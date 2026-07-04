class_name KeybindPanel
extends VBoxContainer
## Key rebinding screen — built entirely in code (same idiom as key_tutorial.gd),
## instanced lazily by main_menu.gd and dropped into Center/VBox alongside the
## other settings sub-panels (see main_menu.gd's _show_panel).
##
## Lists every action in GraphicsSettings.KEYBIND_ACTIONS with its current
## keyboard/mouse bind and (where applicable) gamepad-button bind. Clicking a
## "Rebind" button enters capture mode: the next key / mouse button / gamepad
## button press becomes that slot's new bind; ESC cancels. Conflicts are
## resolved by swapping the event away from whichever other action held it
## (GraphicsSettings.rebind_action's policy) and toasted in the status line.

signal back_pressed

var _status: Label
var _rows_box: VBoxContainer
var _row_widgets: Dictionary = {} # action -> {kb_lbl, kb_btn, pad_lbl, pad_btn}

## Set while listening for the next input event. Null = not capturing.
var _capturing = null # Dictionary {"action": String, "is_gamepad": bool}
var _capture_start_frame: int = -1

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var prompt := Label.new()
	prompt.text = tr("Rebind Controls")
	prompt.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9, 1))
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(prompt)

	_status = Label.new()
	_status.text = tr("Click a bind, then press the new key/button. ESC cancels.")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size = Vector2(560, 0)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows_box)
	add_child(scroll)

	for entry in GraphicsSettings.KEYBIND_ACTIONS:
		_add_row(entry)

	var reset_btn := Button.new()
	reset_btn.custom_minimum_size = Vector2(560, 44)
	reset_btn.text = tr("Reset to Defaults")
	reset_btn.pressed.connect(_on_reset_pressed)
	add_child(reset_btn)

	var back_btn := Button.new()
	back_btn.custom_minimum_size = Vector2(560, 40)
	back_btn.text = tr("Back")
	back_btn.pressed.connect(func():
		_cancel_capture()
		back_pressed.emit())
	add_child(back_btn)

func _add_row(entry: Dictionary) -> void:
	var action: String = entry["action"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var name_lbl := Label.new()
	name_lbl.text = tr(entry["label"])
	name_lbl.custom_minimum_size = Vector2(190, 0)
	row.add_child(name_lbl)

	var kb_lbl := Label.new()
	kb_lbl.custom_minimum_size = Vector2(110, 0)
	kb_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kb_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	row.add_child(kb_lbl)

	var kb_btn := Button.new()
	kb_btn.custom_minimum_size = Vector2(96, 0)
	kb_btn.text = tr("Rebind")
	kb_btn.pressed.connect(func(): _start_capture(action, false))
	row.add_child(kb_btn)

	var pad_lbl := Label.new()
	pad_lbl.custom_minimum_size = Vector2(90, 0)
	pad_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pad_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	row.add_child(pad_lbl)

	var pad_btn := Button.new()
	pad_btn.custom_minimum_size = Vector2(96, 0)
	pad_btn.text = tr("Rebind")
	pad_btn.pressed.connect(func(): _start_capture(action, true))
	row.add_child(pad_btn)

	_rows_box.add_child(row)
	_row_widgets[action] = {"kb_lbl": kb_lbl, "kb_btn": kb_btn, "pad_lbl": pad_lbl, "pad_btn": pad_btn}
	_refresh_row(action)

## Pulls the current kb/mouse and gamepad-button events straight from the live
## InputMap (already reconciled with any saved override by GraphicsSettings)
## and updates one row's labels. Move/fire/aim default to an analog stick or
## trigger on gamepad — rebinding those to a single button doesn't make sense,
## so their pad slot shows a fixed "Stick"/"Trigger" readout instead of a
## button (see GraphicsSettings._factory_default_events for which actions
## that applies to).
func _refresh_row(action: String) -> void:
	var w: Dictionary = _row_widgets.get(action, {})
	if w.is_empty():
		return
	var kb_event: InputEvent = null
	var pad_button_event: InputEvent = null
	var has_axis_only := false
	var events := InputMap.action_get_events(action) if InputMap.has_action(action) else []
	var saw_axis := false
	var saw_button := false
	for e in events:
		if (e is InputEventKey or e is InputEventMouseButton) and kb_event == null:
			kb_event = e
		elif e is InputEventJoypadButton:
			saw_button = true
			if pad_button_event == null:
				pad_button_event = e
		elif e is InputEventJoypadMotion:
			saw_axis = true
	has_axis_only = saw_axis and not saw_button

	w["kb_lbl"].text = _event_label(kb_event)
	if has_axis_only:
		w["pad_lbl"].text = _axis_label(action)
		w["pad_btn"].visible = false
	else:
		w["pad_lbl"].text = _event_label(pad_button_event)
		w["pad_btn"].visible = true

func _axis_label(action: String) -> String:
	if action in ["fire", "aim"]:
		return tr("Trigger")
	return tr("Stick")

func _event_label(e: InputEvent) -> String:
	if e == null:
		return "—"
	if e is InputEventKey:
		var k := e as InputEventKey
		var code: int = k.physical_keycode if k.physical_keycode != 0 else k.keycode
		return OS.get_keycode_string(code) if code != 0 else "—"
	if e is InputEventMouseButton:
		match (e as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return tr("Mouse L")
			MOUSE_BUTTON_RIGHT: return tr("Mouse R")
			MOUSE_BUTTON_MIDDLE: return tr("Mouse M")
			MOUSE_BUTTON_WHEEL_UP: return tr("Wheel Up")
			MOUSE_BUTTON_WHEEL_DOWN: return tr("Wheel Down")
			MOUSE_BUTTON_XBUTTON1: return tr("Mouse 4")
			MOUSE_BUTTON_XBUTTON2: return tr("Mouse 5")
			_: return tr("Mouse %d") % (e as InputEventMouseButton).button_index
	if e is InputEventJoypadButton:
		match (e as InputEventJoypadButton).button_index:
			JOY_BUTTON_A: return "A"
			JOY_BUTTON_B: return "B"
			JOY_BUTTON_X: return "X"
			JOY_BUTTON_Y: return "Y"
			JOY_BUTTON_LEFT_SHOULDER: return "LB"
			JOY_BUTTON_RIGHT_SHOULDER: return "RB"
			JOY_BUTTON_LEFT_STICK: return "L3"
			JOY_BUTTON_RIGHT_STICK: return "R3"
			JOY_BUTTON_START: return tr("Start")
			_: return tr("Pad %d") % (e as InputEventJoypadButton).button_index
	return "—"

func is_capturing() -> bool:
	return _capturing != null

func _start_capture(action: String, is_gamepad: bool) -> void:
	_cancel_capture()
	_capturing = {"action": action, "is_gamepad": is_gamepad}
	_capture_start_frame = Engine.get_process_frames()
	var w: Dictionary = _row_widgets.get(action, {})
	var btn: Button = w.get("pad_btn") if is_gamepad else w.get("kb_btn")
	if btn:
		btn.text = "..." # capture-in-progress ellipsis, not translatable text
	_status.text = tr("Press a key/button for \"%s\" — ESC to cancel.") % tr(_label_for(action))

func _label_for(action: String) -> String:
	for entry in GraphicsSettings.KEYBIND_ACTIONS:
		if entry["action"] == action:
			return entry["label"]
	return action

func _cancel_capture() -> void:
	if _capturing == null:
		return
	var w: Dictionary = _row_widgets.get(_capturing["action"], {})
	var btn: Button = w.get("pad_btn") if _capturing["is_gamepad"] else w.get("kb_btn")
	if btn:
		btn.text = tr("Rebind")
	_capturing = null
	_status.text = tr("Click a bind, then press the new key/button. ESC cancels.")

func _input(event: InputEvent) -> void:
	if _capturing == null:
		return
	# Swallow the very click that opened capture mode (Button emits "pressed"
	# on release, which happens inside this same frame's input flush) so it
	# doesn't get captured as the new bind for itself.
	if Engine.get_process_frames() == _capture_start_frame:
		return

	var is_gamepad: bool = _capturing["is_gamepad"]
	var action: String = _capturing["action"]

	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo:
		if k.physical_keycode == KEY_ESCAPE:
			_cancel_capture()
			get_viewport().set_input_as_handled()
			return
		if not is_gamepad:
			var new_ev := InputEventKey.new()
			new_ev.physical_keycode = k.physical_keycode
			_finish_capture(action, is_gamepad, new_ev)
			get_viewport().set_input_as_handled()
		return

	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and not is_gamepad:
		var new_ev := InputEventMouseButton.new()
		new_ev.button_index = mb.button_index
		_finish_capture(action, is_gamepad, new_ev)
		get_viewport().set_input_as_handled()
		return

	var jb := event as InputEventJoypadButton
	if jb != null and jb.pressed and is_gamepad:
		var new_ev := InputEventJoypadButton.new()
		new_ev.button_index = jb.button_index
		_finish_capture(action, is_gamepad, new_ev)
		get_viewport().set_input_as_handled()
		return
	# Anything else (mouse motion, joypad axis wobble, wrong-category input
	# while listening for the other slot) is ignored — keep listening.

func _finish_capture(action: String, is_gamepad: bool, new_event: InputEvent) -> void:
	var stolen := GraphicsSettings.rebind_action(action, is_gamepad, new_event)
	_capturing = null
	for a in _row_widgets.keys():
		_refresh_row(a)
	AudioBus.play_synth_ui("pickup_health", -8.0, 1.3)
	if stolen.is_empty():
		_status.text = tr("Bound \"%s\" to %s.") % [tr(_label_for(action)), _event_label(new_event)]
	else:
		_status.text = tr("Bound \"%s\" to %s — removed from: %s") % [tr(_label_for(action)), _event_label(new_event), ", ".join(stolen.map(func(l): return tr(l)))]

func _on_reset_pressed() -> void:
	_cancel_capture()
	GraphicsSettings.reset_keybinds_to_default()
	for a in _row_widgets.keys():
		_refresh_row(a)
	_status.text = tr("All controls reset to defaults.")
	AudioBus.play_synth_ui("pickup_health", -8.0, 1.2)
