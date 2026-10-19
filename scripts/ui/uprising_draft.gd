extends Control
## UPRISING MODE draft, between sectors: three patches (GameState.uprising
## offers), each a buff with a cost, plus a reroll for compute. Picking one
## deploys to the next sector (GameState.uprising_pick). Built in code like
## the rest of the menus' dynamic parts. Covered by tests/uprising_probe; the
## look by tests/uprising_draft_shot (windowed).

const COL := Color(0.45, 1.0, 0.75)
const COL_DIM := Color(0.6, 0.7, 0.68)
const COL_BUFF := Color(0.5, 1.0, 0.6)
const COL_COST := Color(1.0, 0.45, 0.4)
const COL_BOSS := Color(1.0, 0.35, 0.3)
const FONT := preload("res://assets/fonts/Orbitron.ttf")
const BACKDROP := preload("res://assets/textures/ui/menu_background.png")

var buttons: Array[Button] = [] ## The offer buttons, in offer order.
var _box: VBoxContainer
var _cards: VBoxContainer
var _reroll: Button
var _info: Label

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var th := Theme.new()
	th.default_font = FONT
	th.default_font_size = 20
	theme = th
	var bg := TextureRect.new()
	bg.texture = BACKDROP
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.modulate = Color(0.28, 0.3, 0.34)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(820, 0)
	_box.add_theme_constant_override("separation", 14)
	center.add_child(_box)
	var u: Dictionary = GameState.uprising
	var title := Label.new()
	title.text = tr("SECTOR %d/%d CLEARED") % [int(u.get("sector", 0)), (u.get("levels", []) as Array).size()]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", COL)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	_box.add_child(title)
	_box.add_child(_sector_strip(u))
	var sub := Label.new()
	sub.text = tr("Draft one patch for the rest of the run.")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", COL_DIM)
	_box.add_child(sub)
	_info = Label.new()
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 16)
	_info.add_theme_color_override("font_color", COL_DIM)
	_box.add_child(_info)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 10)
	_box.add_child(_cards)
	_reroll = Button.new()
	_reroll.add_theme_font_size_override("font_size", 16)
	_reroll.pressed.connect(_on_reroll)
	_box.add_child(_reroll)
	_build_offers()

## The run at a glance: cleared sectors ticked, the next one lit, the boss in red.
func _sector_strip(u: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var levels: Array = u.get("levels", [])
	var at := int(u.get("sector", 0))
	for i in levels.size():
		var lid := GameState.level_id_from_path(String(levels[i]))
		var boss := i == levels.size() - 1
		var l := Label.new()
		var title := tr(LevelDefs.level_title(lid)).get_slice(" — ", 0)
		if i < at:
			l.text = "✔ " + title
			l.add_theme_color_override("font_color", Color(0.45, 0.55, 0.5))
		elif i == at:
			l.text = "▶ " + title
			l.add_theme_color_override("font_color", COL_BOSS if boss else Color(1, 1, 1))
		else:
			l.text = (tr("BOSS") + ": " if boss else "") + title
			l.add_theme_color_override("font_color", COL_BOSS if boss else COL_DIM)
		l.add_theme_font_size_override("font_size", 14)
		row.add_child(l)
		if i < levels.size() - 1:
			var sep := Label.new()
			sep.text = "›"
			sep.add_theme_color_override("font_color", COL_DIM)
			row.add_child(sep)
	return row

## A patch card: its name, then the buff in green and the cost in red. A patch's
## description is "<buff>, <cost>" in every language, split at the last ", ".
func _card(p: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(820, 92)
	# Solid panels: the backdrop art showing through the default button made the
	# buff and cost lines hard to read (seen in uprising_draft_shot).
	for st in ["normal", "hover", "focus", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.05, 0.06, 0.92) if st != "hover" else Color(0.06, 0.12, 0.11, 0.95)
		sb.set_border_width_all(2 if st in ["hover", "focus"] else 1)
		sb.border_color = COL if st in ["hover", "focus"] else Color(0.25, 0.35, 0.33)
		sb.set_corner_radius_all(4)
		b.add_theme_stylebox_override(st, sb)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	b.add_child(v)
	var desc := tr(String(p["desc"]))
	var cut := desc.rfind(", ")
	var lines := [[tr(String(p["name"])), Color(1, 1, 1), 22],
		["▲ " + (desc.substr(0, cut) if cut > 0 else desc), COL_BUFF, 17]]
	if cut > 0:
		lines.append(["▼ " + desc.substr(cut + 2), COL_COST, 17])
	for ln in lines:
		var l := Label.new()
		l.text = ln[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_color_override("font_color", ln[1])
		l.add_theme_font_size_override("font_size", ln[2])
		v.add_child(l)
	return b

## (Re)build the offer cards and the info line from GameState.uprising.
func _build_offers() -> void:
	for b in buttons:
		b.queue_free()
	buttons.clear()
	var u: Dictionary = GameState.uprising
	for id in u.get("offers", []):
		var b := _card(GameState.uprising_patch(String(id)))
		b.pressed.connect(pick.bind(String(id)))
		_cards.add_child(b)
		buttons.append(b)
	var have: Array = (u.get("patches", []) as Array).map(func(x): return tr(String(GameState.uprising_patch(String(x))["name"])))
	var compute := int(GameState.uprising_record()["compute"])
	_info.text = (tr("Patches: %s") % (", ".join(PackedStringArray(have)) if not have.is_empty() else "-")) \
		+ "   ·   " + (tr("Reboots left: %d") % int(u.get("lives", 0)))
	_reroll.text = tr("Reroll (%d compute, you have %d)") % [GameState.UPRISING_REROLL_COST, compute]
	_reroll.disabled = compute < GameState.UPRISING_REROLL_COST
	if not buttons.is_empty():
		buttons[0].grab_focus.call_deferred()

func pick(id: String) -> void:
	for b in buttons:
		b.disabled = true
	_reroll.disabled = true
	GameState.uprising_pick(id)

func _on_reroll() -> void:
	if GameState.uprising_reroll():
		_build_offers()
