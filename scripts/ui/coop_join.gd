class_name CoopJoin
extends CanvasLayer
## The co-op join overlay (#402, stage 5): "press A on the second controller".
## The first pad button pressed joins that pad as player two
## (PlayerInput.setup_coop); player one keeps the keyboard and any other
## connected pad. Back closes it without joining. tests/coop_menu_probe.

signal joined(pad: int)

func _ready() -> void:
	layer = 20
	# A CanvasLayer cuts theme inheritance: borrow the menu's (its font) directly.
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	if get_parent() is Control:
		root.theme = (get_parent() as Control).theme
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	var title := Label.new()
	title.text = tr("CO-OP")
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var hint := Label.new()
	hint.text = tr("Player two: press A on the second controller")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	var pads := Label.new()
	pads.text = tr("Controllers connected: %d") % Input.get_connected_joypads().size()
	pads.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pads.modulate = Color(1, 1, 1, 0.7)
	box.add_child(pads)
	var back := Button.new()
	back.name = "Back"
	back.text = tr("Back")
	back.custom_minimum_size = Vector2(240, 44)
	back.pressed.connect(queue_free)
	box.add_child(back)
	back.grab_focus.call_deferred()

func _input(event: InputEvent) -> void:
	var jb := event as InputEventJoypadButton
	if jb == null or not jb.pressed:
		return
	get_viewport().set_input_as_handled()
	var p1 := -1
	for d in Input.get_connected_joypads():
		if d != jb.device:
			p1 = d
			break
	PlayerInput.setup_coop(p1, jb.device)
	AudioBus.play_synth_ui("pickup_clink", -6.0)
	joined.emit(jb.device)
	queue_free()
