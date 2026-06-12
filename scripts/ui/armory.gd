class_name Armory
extends CanvasLayer
## Between-levels upgrade shop, shown by the level briefing before deploying.
## Spend run score on the three permanent weapon tracks (GameState.upgrades).
## Keyboard-driven (1/2/3 to buy, ENTER/SPACE to deploy) so it needs no mouse
## capture juggling. Emits `deployed` when the player moves on.

signal deployed

const KEYS := ["damage", "mag", "reload"]
const PIP_ON := "◼"
const PIP_OFF := "◻"

var _rows: Array[Label] = []
var _score_lbl: Label
var _hint: Label

func _ready() -> void:
	layer = 60
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.04, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)
	var title := Label.new()
	title.text = "RESISTANCE ARMORY"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.55, 0.95, 0.9))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_score_lbl = Label.new()
	_score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	vbox.add_child(_score_lbl)
	vbox.add_child(HSeparator.new())
	for i in KEYS.size():
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 20)
		vbox.add_child(row)
		_rows.append(row)
	vbox.add_child(HSeparator.new())
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	_hint.text = "[1] [2] [3] — buy upgrade      [ENTER] — deploy"
	vbox.add_child(_hint)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()

func _refresh() -> void:
	_score_lbl.text = "SCORE: %d" % GameState.score
	for i in KEYS.size():
		var k: String = KEYS[i]
		var lvl := GameState.upgrade_level(k)
		var defn: Dictionary = GameState.UPGRADE_DEFS[k]
		var pips := PIP_ON.repeat(lvl) + PIP_OFF.repeat(GameState.UPGRADE_MAX - lvl)
		var tail: String
		if lvl >= GameState.UPGRADE_MAX:
			tail = "MAXED"
		else:
			tail = "%d pts" % GameState.upgrade_cost(k)
		_rows[i].text = "[%d]  %-14s %s  +%d%%/rank   %s" % [
			i + 1, defn["label"], pips, int(defn["per"] * 100), tail]
		var afford := lvl < GameState.UPGRADE_MAX and GameState.score >= GameState.upgrade_cost(k)
		_rows[i].add_theme_color_override("font_color",
			Color(0.9, 0.95, 0.93) if afford else Color(0.45, 0.48, 0.52))

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_1, KEY_KP_1: _buy("damage")
		KEY_2, KEY_KP_2: _buy("mag")
		KEY_3, KEY_KP_3: _buy("reload")
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			get_viewport().set_input_as_handled()
			deployed.emit()
			queue_free()

func _buy(k: String) -> void:
	get_viewport().set_input_as_handled()
	if GameState.buy_upgrade(k):
		AudioBus.play_synth_ui("pickup_clink", -4.0, 1.2)
	else:
		AudioBus.play_synth_ui("empty_click", -8.0, 0.8)
	_refresh()
