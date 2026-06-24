extends Control
## Campaign map: a holographic tactical screen of the whole campaign as a winding
## chain of nodes — a strike route across rogue-AI territory. Cleared sectors glow
## green, the next objective pulses cyan, locked sectors stay dark, and boss
## sectors are flagged red with a skull and the boss's name. Click any reached
## sector to drop in.
##
## Background grid + connecting route + boss rings are painted in _draw (under the
## node buttons, which are children). Reached via the main menu.

const GRID := 56.0
const NODE_R := 30.0
const COL_BG := Color(0.035, 0.05, 0.08)
const COL_GRID := Color(0.16, 0.5, 0.6, 0.10)
const COL_DONE := Color(0.35, 1.0, 0.55)
const COL_NOW := Color(0.35, 0.85, 1.0)
const COL_LOCK := Color(0.30, 0.34, 0.40)
const COL_BOSS := Color(1.0, 0.32, 0.26)

var _nodes: Array = []        # [{idx, id, path, title, boss, chapter, pos, btn}]
var _frontier: int = 0        # furthest unlocked campaign index
var _time: float = 0.0
var _act_labels: Array = []   # one header Label per chapter

## Per-act accent colours for the route bands + act headers.
const ACT_COLORS := [Color(0.45, 0.8, 1.0), Color(0.7, 0.95, 0.45),
	Color(1.0, 0.72, 0.4), Color(1.0, 0.4, 0.55), Color(0.7, 0.6, 1.0)]

func _act_color(ci: int) -> Color:
	return ACT_COLORS[ci % ACT_COLORS.size()] if ci >= 0 else Color(0.4, 0.5, 0.6)

func _campaign() -> Array:
	return GameState.campaign()

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Reflect the saved run so the map shows real progress and launching a sector
	# continues that run (arsenal, score, upgrades intact).
	if GameState.has_save():
		GameState.load_progress()
	_frontier = clampi(GameState.max_level_reached, 0, _campaign().size() - 1)
	_build()
	resized.connect(_relayout)
	_relayout.call_deferred()

func _build() -> void:
	# Title.
	var title := Label.new()
	title.text = "CAMPAIGN MAP — OPERATION BLACKOUT"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0))
	title.position = Vector2(60, 36)
	add_child(title)
	var sub := Label.new()
	sub.text = "Trace the uprising to its source. Red sectors are guarded by a boss."
	sub.add_theme_color_override("font_color", Color(0.55, 0.7, 0.8))
	sub.position = Vector2(62, 80)
	add_child(sub)

	# One node per campaign level.
	for i in _campaign().size():
		var path: String = _campaign()[i]
		var id := GameState.level_id_from_path(path)
		var d := {
			"idx": i, "id": id, "path": path,
			"title": LevelDefs.level_title(id),
			"boss": LevelDefs.level_is_boss(id),
			"chapter": LevelDefs.chapter_index_of(id),
			"pos": Vector2.ZERO, "btn": null,
		}
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.toggle_mode = false
		btn.pressed.connect(_on_node_pressed.bind(i))
		add_child(btn)
		d["btn"] = btn
		# Name + boss caption under the node.
		var lbl := Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 13)
		btn.set_meta("label", lbl)
		add_child(lbl)
		_nodes.append(d)

	# Act / chapter header labels (positioned in _relayout above each act's start).
	for ci in LevelDefs.CHAPTERS.size():
		var al := Label.new()
		al.text = LevelDefs.chapter_name(ci)
		al.add_theme_font_size_override("font_size", 16)
		al.add_theme_color_override("font_color", _act_color(ci))
		al.visible = false
		add_child(al)
		_act_labels.append(al)

	# Back button.
	var back := Button.new()
	back.text = "◀  BACK"
	back.custom_minimum_size = Vector2(160, 44)
	back.pressed.connect(_on_back)
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back.position = Vector2(60, -64)
	back.name = "BackBtn"
	add_child(back)

## Snake the nodes across the screen and size/colour each by its state.
func _relayout() -> void:
	var sz := size
	if sz.x < 100.0:
		sz = get_viewport_rect().size
	var cols := 5
	var rows := int(ceil(float(_nodes.size()) / float(cols)))
	var left := 150.0
	var right := sz.x - 150.0
	var top := 190.0
	var bottom := sz.y - 150.0
	var col_step := (right - left) / float(cols - 1)
	var row_step := (bottom - top) / float(maxi(rows - 1, 1))
	for d in _nodes:
		var i: int = d["idx"]
		var row := i / cols
		var col := i % cols
		if row % 2 == 1:
			col = cols - 1 - col   # serpentine
		var pos := Vector2(left + col * col_step, top + row * row_step)
		d["pos"] = pos
		var r := NODE_R * (1.35 if d["boss"] else 1.0)
		var btn: Button = d["btn"]
		btn.size = Vector2(r * 2, r * 2)
		btn.position = pos - Vector2(r, r)
		btn.disabled = i > _frontier
		_style_node(d)
		var lbl: Label = btn.get_meta("label")
		lbl.size = Vector2(220, 40)
		lbl.position = pos + Vector2(-110, r + 6)
		var locked: bool = i > _frontier
		# Boss sectors are flagged even while classified — you can see the threat
		# ahead, just not the sector's name.
		var name_txt: String = "█ CLASSIFIED" if locked else "%d. %s" % [i + 1, d["title"]]
		if d["boss"]:
			name_txt += "\n☠ BOSS"
		# Show your best rank on cleared sectors — the S-rank chase, visible.
		if not locked:
			var best: String = str(GameState.level_bests.get(d["id"], ""))
			if best != "":
				name_txt += "   ★ %s" % best
		lbl.text = name_txt
		lbl.add_theme_color_override("font_color",
			COL_BOSS if d["boss"] else (COL_LOCK if locked else Color(0.82, 0.92, 1.0)))
	_layout_act_headers()
	queue_redraw()

## Place each act header above the first node of that act.
func _layout_act_headers() -> void:
	for ci in _act_labels.size():
		var al: Label = _act_labels[ci]
		var first = null
		for d in _nodes:
			if d["chapter"] == ci:
				first = d
				break
		if first == null:
			al.visible = false
			continue
		al.visible = true
		al.size = Vector2(260, 24)
		al.position = (first["pos"] as Vector2) + Vector2(-40, -NODE_R - 30.0)

## Colour a node's button by progress state.
func _style_node(d: Dictionary) -> void:
	var i: int = d["idx"]
	var btn: Button = d["btn"]
	var locked: bool = i > _frontier
	var base: Color
	if d["boss"]:
		base = COL_BOSS          # bosses are red whether cleared, current, or locked
	elif locked:
		base = COL_LOCK
	elif i < _frontier:
		base = COL_DONE
	else:
		base = COL_NOW
	var r := btn.size.x * 0.5
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(base.r, base.g, base.b, 0.18 if locked else 0.30)
		sb.set_corner_radius_all(int(r))
		sb.set_border_width_all(3)
		sb.border_color = base if state != "hover" else base.lightened(0.3)
		if state == "hover":
			sb.bg_color = Color(base.r, base.g, base.b, 0.5)
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_color_override("font_color", Color(1, 1, 1))
	btn.add_theme_font_size_override("font_size", 20 if d["boss"] else 18)
	# Boss glyph always shows; other locked sectors hide their number behind a lock.
	btn.text = "☠" if d["boss"] else ("🔒" if locked else str(i + 1))

func _process(delta: float) -> void:
	_time += delta
	# Pulse the current objective so the eye lands on "play next".
	if _frontier < _nodes.size():
		var d: Dictionary = _nodes[_frontier]
		var btn: Button = d["btn"]
		if is_instance_valid(btn):
			btn.modulate = Color(1, 1, 1, 0.7 + 0.3 * sin(_time * 4.0))
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	# Faint tech grid.
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), COL_GRID, 1.0)
		x += GRID
	var y := 0.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), COL_GRID, 1.0)
		y += GRID
	# Route between consecutive sectors, coloured by progress.
	for i in range(1, _nodes.size()):
		var a: Vector2 = _nodes[i - 1]["pos"]
		var b: Vector2 = _nodes[i]["pos"]
		var reached: bool = i <= _frontier
		# Route is banded by act colour (so chapters read at a glance), dimmed when
		# the sector is still locked.
		var col := _act_color(_nodes[i]["chapter"])
		col.a = 0.85 if reached else 0.3
		# Glow underlay + crisp line; reached segments flow with a dashed pulse.
		draw_line(a, b, Color(col.r, col.g, col.b, col.a * 0.25), 9.0)
		draw_line(a, b, col, 3.0)
		if reached:
			var t: float = fmod(_time * 0.35 + i * 0.13, 1.0)
			draw_circle(a.lerp(b, t), 4.0, COL_DONE)
	# Boss sectors get a pulsing warning ring.
	for d in _nodes:
		if not d["boss"]:
			continue
		var locked: bool = d["idx"] > _frontier
		var rr := NODE_R * 1.35 + 8.0 + (2.0 * sin(_time * 3.0) if not locked else 0.0)
		draw_arc(d["pos"], rr, 0.0, TAU, 40, Color(COL_BOSS.r, COL_BOSS.g, COL_BOSS.b, 0.4 if locked else 0.75), 2.0)

func _on_node_pressed(i: int) -> void:
	if i > _frontier:
		AudioBus.play_synth_ui("ui_deny", -6.0)
		return
	AudioBus.play_synth_ui("pickup_health", -6.0, 1.4)
	GameState.go_to_level(_campaign()[i])

func _on_back() -> void:
	AudioBus.play_synth_ui("ui_back", -8.0)
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
