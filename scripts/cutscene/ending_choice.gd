class_name EndingChoice
extends CanvasLayer
## The finale's choice: ARCHON is down but its last spark still runs, and the
## player decides what happens to it (StoryArc.ENDINGS). Shown by
## victory_cutscene.gd once its 3D timeline ends; a locked ending stays on screen,
## disabled, naming what opens it (and how far this run got), so a second run has
## something to chase. Picking one records it (GameState.record_ending) and emits
## `chosen`; transmission_for(id) builds that ending's closing broadcast.
## Covered by tests/ending_choice_probe.

signal chosen(id: String)

const COL := Color(0.45, 1.0, 0.75)
const COL_DIM := Color(0.55, 0.62, 0.6)
const FONT := preload("res://assets/fonts/Orbitron.ttf")

var buttons: Dictionary = {} ## ending id -> Button
var _texts: Dictionary = {}  ## ending id -> what its button says, for probes

## A VictoryTransmission carrying ending `id`'s header and lines.
static func transmission_for(id: String) -> VictoryTransmission:
	var e: Dictionary = StoryArc.ENDINGS.get(id, StoryArc.ENDINGS["shutdown"])
	var x := VictoryTransmission.new()
	x.header_text = String(e["header"])
	x.lines = PackedStringArray(e["lines"])
	return x

func button_text(id: String) -> String:
	return String(_texts.get(id, ""))

func _ready() -> void:
	layer = 20
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var th := Theme.new()
	th.default_font = FONT
	th.default_font_size = 20
	root.theme = th
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.01, 0.02, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(760, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var head := Label.new()
	head.text = tr("ARCHON'S LAST SPARK IS STILL RUNNING.")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 32)
	head.add_theme_color_override("font_color", COL)
	box.add_child(head)
	var sub := Label.new()
	sub.text = tr("What do you do with it?")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", COL_DIM)
	box.add_child(sub)
	var seen: Array = GameState.endings_seen()
	var first: Button = null
	for id in StoryArc.ENDING_ORDER:
		var e: Dictionary = StoryArc.ENDINGS[id]
		var open := StoryArc.ending_open(id, GameState.run_hijacks, GameState.run_breaches)
		var b := Button.new()
		b.custom_minimum_size = Vector2(760, 84)
		var text := tr(String(e["title"])) + "\n" + tr(String(e["desc"]))
		if not open:
			text += "\n" + _need_text(String(e.get("need", "")))
		elif seen.has(id):
			text += "   ✔ " + tr("SEEN")
		b.text = text
		_texts[id] = text
		b.disabled = not open
		b.pressed.connect(_pick.bind(id))
		box.add_child(b)
		buttons[id] = b
		if open and first == null:
			first = b
	if first:
		first.grab_focus.call_deferred()

## "LOCKED · hijack 3 robots in one run (2/3)".
func _need_text(need: String) -> String:
	if need == "hijacks":
		return tr("LOCKED · hijack %d robots in one run (%d/%d)") % [StoryArc.ENDING_HIJACKS,
			mini(GameState.run_hijacks, StoryArc.ENDING_HIJACKS), StoryArc.ENDING_HIJACKS]
	if need == "breaches":
		return tr("LOCKED · network breach %d machines in one run (%d/%d)") % [StoryArc.ENDING_BREACHES,
			mini(GameState.run_breaches, StoryArc.ENDING_BREACHES), StoryArc.ENDING_BREACHES]
	return tr("LOCKED")

func _pick(id: String) -> void:
	for b in buttons.values():
		(b as Button).disabled = true
	GameState.record_ending(id)
	AudioBus.play_synth_ui("overlord_glitch", -4.0, 0.8)
	chosen.emit(id)
