extends Node
## Probe: the co-op menu entry, stage 5 of local co-op (#402). On the main menu:
## (1) a Co-op button sits with the main buttons and reads OFF;
## (2) pressing it opens the join overlay ("press A on the second controller");
##     a keyboard key does not join;
## (3) a button press on a pad joins that pad as player two (PlayerInput.coop_on,
##     p2_device = that pad, player one keeps the keyboard), closes the overlay
##     and the button names the pad;
## (4) pressing the button again leaves co-op (reset_coop) and it reads OFF;
## (5) Back on the overlay closes it without joining.
##   godot --headless --path . --audio-driver Dummy res://tests/coop_menu_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

## The open join overlay, or null. A freed one compares equal to null but
## still raises on a method call, so callers only ever test this for null.
func _overlay(menu: Node) -> Node:
	for n in menu.get_children():
		if n is CoopJoin and not n.is_queued_for_deletion():
			return n
	return null

func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)

func _pad(device: int) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = JOY_BUTTON_A
	e.pressed = true
	Input.parse_input_event(e)

func _run() -> void:
	PlayerInput.reset_coop()
	var menu: Node = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _frames(5)
	var btn := menu.get_node_or_null("Center/VBox/MainButtons/Coop") as Button
	_check("a Co-op button sits with the main buttons", btn != null)
	if btn == null:
		_finish()
		return
	_check("it reads OFF", btn.text.contains(tr("OFF")), btn.text)

	# 2. The overlay; a key does not join.
	btn.pressed.emit()
	await _frames(2)
	var ov := _overlay(menu)
	_check("pressing it opens the join overlay", ov != null)
	_key(KEY_SPACE)
	await _frames(3)
	_check("a keyboard key does not join", not PlayerInput.coop_on)

	# 3. A pad joins as player two.
	_pad(1)
	await _frames(3)
	_check("a pad's button joins co-op", PlayerInput.coop_on)
	_check("that pad is player two's", PlayerInput.p2_device == 1, str(PlayerInput.p2_device))
	_check("player one keeps the keyboard (and no pad 1)", PlayerInput.p1_device != 1, str(PlayerInput.p1_device))
	_check("the overlay closes", _overlay(menu) == null)
	_check("the button names the pad", btn.text.contains(tr("ON")) and btn.text.contains("2"), btn.text)

	# 4. Leave.
	btn.pressed.emit()
	await _frames(2)
	_check("pressing it again leaves co-op", not PlayerInput.coop_on and PlayerInput.p2_device == -1)
	_check("it reads OFF again", btn.text.contains(tr("OFF")), btn.text)
	var stray := _overlay(menu)
	_check("leaving opens no overlay", stray == null)

	# 5. Back closes the overlay without joining.
	btn.pressed.emit()
	await _frames(2)
	ov = _overlay(menu)
	var back := ov.find_child("Back", true, false) as Button if ov else null
	_check("the overlay has a Back button", back != null)
	if back:
		back.pressed.emit()
		await _frames(2)
		_check("Back closes it without joining", _overlay(menu) == null and not PlayerInput.coop_on)
	_finish()

func _finish() -> void:
	PlayerInput.reset_coop()
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
