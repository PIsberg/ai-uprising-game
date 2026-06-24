class_name Armory
extends CanvasLayer
## Between-levels upgrade shop, shown by the level briefing before deploying.
## Spend run score on the three permanent weapon tracks (GameState.upgrades).
## A holographic card rack (matching the campaign map's look): click a card's BUY
## button or press 1/2/3; ENTER/SPACE deploys. Emits `deployed` when moving on.

signal deployed

const KEYS := ["damage", "mag", "reload"]
## Per-track presentation (icon glyph, blurb, accent) layered over GameState's defs.
const META := {
	"damage": {"icon": "✦", "desc": "More punch per shot", "color": Color(1.0, 0.45, 0.35)},
	"mag":    {"icon": "▤", "desc": "Bigger magazines", "color": Color(0.45, 0.75, 1.0)},
	"reload": {"icon": "↻", "desc": "Faster reloads", "color": Color(0.5, 0.95, 0.6)},
}

var _cards: Dictionary = {}   # key -> {segs:[ColorRect], cost:Label, buy:Button, box:StyleBoxFlat, accent}
var _score_lbl: Label
var _scan: ColorRect

func _ready() -> void:
	layer = 60
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.04, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Main holographic console panel.
	var panel := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.04, 0.08, 0.11, 0.96)
	psb.set_corner_radius_all(14)
	psb.set_border_width_all(2)
	psb.border_color = Color(0.3, 0.7, 0.85, 0.8)
	psb.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", psb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	# --- header: title + credits chip ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 30)
	vbox.add_child(header)
	var titlebox := VBoxContainer.new()
	titlebox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titlebox)
	var title := Label.new()
	title.text = "RESISTANCE ARMORY"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.6, 0.95, 0.95))
	titlebox.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Salvaged tech — spend it before you deploy."
	subtitle.add_theme_color_override("font_color", Color(0.5, 0.65, 0.75))
	titlebox.add_child(subtitle)
	# Credits chip.
	var chip := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.12, 0.1, 0.03, 0.95)
	csb.set_corner_radius_all(8)
	csb.set_border_width_all(2)
	csb.border_color = Color(1.0, 0.82, 0.35)
	csb.set_content_margin_all(10)
	chip.add_theme_stylebox_override("panel", csb)
	header.add_child(chip)
	_score_lbl = Label.new()
	_score_lbl.add_theme_font_size_override("font_size", 22)
	_score_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	_score_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(_score_lbl)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# --- the three upgrade cards, side by side ---
	var rack := HBoxContainer.new()
	rack.add_theme_constant_override("separation", 18)
	rack.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(rack)
	for i in KEYS.size():
		_make_card(rack, KEYS[i], i)

	# --- footer: hint + deploy ---
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(footer)
	var hint := Label.new()
	hint.text = "1 / 2 / 3 or click BUY"
	hint.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)
	var deploy := Button.new()
	deploy.text = "DEPLOY  ▶  (ENTER)"
	deploy.custom_minimum_size = Vector2(240, 48)
	deploy.focus_mode = Control.FOCUS_NONE
	deploy.add_theme_font_size_override("font_size", 20)
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.1, 0.3, 0.18, 0.95)
	dsb.set_corner_radius_all(8)
	dsb.set_border_width_all(2)
	dsb.border_color = Color(0.5, 1.0, 0.6)
	deploy.add_theme_stylebox_override("normal", dsb)
	deploy.add_theme_color_override("font_color", Color(0.8, 1.0, 0.85))
	deploy.pressed.connect(_deploy)
	footer.add_child(deploy)

	# Sweeping scanline over the whole screen for that holo-console life.
	_scan = ColorRect.new()
	_scan.color = Color(0.4, 0.85, 1.0, 0.05)
	_scan.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_scan.custom_minimum_size = Vector2(0, 90)
	_scan.size.y = 90
	_scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scan)
	var h: float = get_viewport().get_visible_rect().size.y
	var tw := create_tween().set_loops()
	tw.tween_property(_scan, "position:y", h, 4.5).from(-90.0)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()

func _make_card(rack: HBoxContainer, k: String, idx: int) -> void:
	var m: Dictionary = META[k]
	var accent: Color = m["color"]
	var defn: Dictionary = GameState.UPGRADE_DEFS[k]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(230, 320)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.1, 0.13, 0.96)
	box.set_corner_radius_all(12)
	box.set_border_width_all(2)
	box.border_color = accent
	box.set_content_margin_all(16)
	card.add_theme_stylebox_override("panel", box)
	rack.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vb)

	var icon := Label.new()
	icon.text = m["icon"]
	icon.add_theme_font_size_override("font_size", 56)
	icon.add_theme_color_override("font_color", accent)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(icon)

	var name := Label.new()
	name.text = "[%d]  %s" % [idx + 1, defn["label"]]
	name.add_theme_font_size_override("font_size", 18)
	name.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(name)

	var desc := Label.new()
	desc.text = m["desc"]
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.55, 0.65, 0.72))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(desc)

	var per := Label.new()
	per.text = "+%d%% per rank" % int(float(defn["per"]) * 100)
	per.add_theme_font_size_override("font_size", 14)
	per.add_theme_color_override("font_color", accent)
	per.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(per)

	# Segmented rank bar.
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 4)
	vb.add_child(bar)
	var segs: Array = []
	for s in GameState.UPGRADE_MAX:
		var seg := ColorRect.new()
		seg.custom_minimum_size = Vector2(26, 12)
		bar.add_child(seg)
		segs.append(seg)

	var cost := Label.new()
	cost.add_theme_font_size_override("font_size", 16)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(cost)

	var buy := Button.new()
	buy.focus_mode = Control.FOCUS_NONE
	buy.custom_minimum_size = Vector2(0, 40)
	buy.pressed.connect(_buy.bind(k))
	vb.add_child(buy)

	_cards[k] = {"segs": segs, "cost": cost, "buy": buy, "box": box, "accent": accent}

func _refresh() -> void:
	_score_lbl.text = "CREDITS  %d" % GameState.score
	for k in KEYS:
		var c: Dictionary = _cards[k]
		var accent: Color = c["accent"]
		var lvl := GameState.upgrade_level(k)
		var maxed := lvl >= GameState.UPGRADE_MAX
		for s in c["segs"].size():
			(c["segs"][s] as ColorRect).color = accent if s < lvl else Color(0.16, 0.19, 0.23)
		var cost_lbl: Label = c["cost"]
		var buy: Button = c["buy"]
		var box: StyleBoxFlat = c["box"]
		if maxed:
			cost_lbl.text = "★ MAXED"
			cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
			buy.disabled = true
			buy.text = "MAXED"
			box.border_color = Color(1.0, 0.82, 0.35)
		else:
			var price := GameState.upgrade_cost(k)
			var afford := GameState.score >= price
			cost_lbl.text = "%d cr" % price
			cost_lbl.add_theme_color_override("font_color",
				Color(0.85, 0.95, 0.9) if afford else Color(0.7, 0.45, 0.42))
			buy.disabled = not afford
			buy.text = "BUY" if afford else "NEED %d" % price
			# Affordable cards glow brighter; unaffordable dim.
			box.border_color = accent if afford else Color(accent.r, accent.g, accent.b, 0.35)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_1, KEY_KP_1: _buy("damage")
		KEY_2, KEY_KP_2: _buy("mag")
		KEY_3, KEY_KP_3: _buy("reload")
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			get_viewport().set_input_as_handled()
			_deploy()

func _deploy() -> void:
	deployed.emit()
	queue_free()

func _buy(k: String) -> void:
	get_viewport().set_input_as_handled()
	if GameState.buy_upgrade(k):
		AudioBus.play_synth_ui("pickup_clink", -4.0, 1.2)
		_pop_card(k)
	else:
		AudioBus.play_synth_ui("empty_click", -8.0, 0.8)
	_refresh()

## A quick scale-pop on the card just bought, for tactile feedback.
func _pop_card(k: String) -> void:
	var buy: Button = _cards[k]["buy"]
	var card := buy.get_parent().get_parent() as Control  # vb → card
	if card == null:
		return
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2(1.06, 1.06)
	var tw := card.create_tween()
	tw.tween_property(card, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
