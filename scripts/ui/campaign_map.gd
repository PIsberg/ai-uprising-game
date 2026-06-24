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
var _hover_idx: int = -1      # node the cursor is over (-1 = none), drives the intel panel
var _ping_t: float = 0.0      # 0..1 expanding-ring animation when a node is hovered
var _intel: PanelContainer    # right-hand "sector intel" readout
var _intel_title: Label
var _intel_act: Label
var _intel_body: Label

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
		btn.mouse_entered.connect(_hover_node.bind(i))
		btn.mouse_exited.connect(_unhover_node.bind(i))
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

	_build_intel()

## Right-hand holographic readout: hover any sector to pull its intel — hostiles,
## objective, your best rank — turning the map into a tactical briefing you read,
## not just a row of buttons.
func _build_intel() -> void:
	_intel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.1, 0.14, 0.82)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.3, 0.7, 0.85, 0.7)
	sb.set_content_margin_all(16)
	_intel.add_theme_stylebox_override("panel", sb)
	_intel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_intel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_intel.add_child(vb)
	_intel_title = Label.new()
	_intel_title.add_theme_font_size_override("font_size", 22)
	_intel_title.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0))
	_intel_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_intel_title)
	_intel_act = Label.new()
	_intel_act.add_theme_font_size_override("font_size", 13)
	vb.add_child(_intel_act)
	var sep := HSeparator.new()
	vb.add_child(sep)
	_intel_body = Label.new()
	_intel_body.add_theme_font_size_override("font_size", 14)
	_intel_body.add_theme_color_override("font_color", Color(0.78, 0.9, 0.96))
	_intel_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_intel_body)
	_set_intel(-1)

## Snake the nodes across the screen and size/colour each by its state.
func _relayout() -> void:
	var sz := size
	if sz.x < 100.0:
		sz = get_viewport_rect().size
	var cols := 5
	var rows := int(ceil(float(_nodes.size()) / float(cols)))
	# Reserve a right-hand strip for the intel panel (when the screen is wide
	# enough); the serpentine route packs into the space that's left.
	var intel_w := 320.0 if sz.x > 1100.0 else 0.0
	var left := 150.0
	var right := sz.x - 150.0 - intel_w
	var top := 190.0
	var bottom := sz.y - 150.0
	if _intel:
		if intel_w > 0.0:
			_intel.visible = true
			_intel.position = Vector2(sz.x - intel_w - 20.0, top)
			_intel.size = Vector2(intel_w, bottom - top)
		else:
			_intel.visible = false
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
	_ping_t = minf(1.0, _ping_t + delta * 2.2)
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

	# --- hologram juice ---
	# A scanline band sweeping down the screen (CRT/holo read).
	var sy := fmod(_time * 95.0, size.y + 160.0) - 80.0
	draw_rect(Rect2(0, sy - 34, size.x, 68), Color(0.3, 0.7, 0.95, 0.025))
	draw_line(Vector2(0, sy), Vector2(size.x, sy), Color(0.45, 0.85, 1.0, 0.10), 2.0)
	# "Deploy ready" rotating corner brackets around the current objective.
	if _frontier < _nodes.size():
		var fp: Vector2 = _nodes[_frontier]["pos"]
		var fr := NODE_R * (1.35 if _nodes[_frontier]["boss"] else 1.0) + 12.0
		for q in 4:
			var b0 := _time * 1.4 + q * (TAU / 4.0)
			draw_arc(fp, fr, b0 + 0.12, b0 + 0.62, 8, Color(0.45, 0.95, 1.0, 0.85), 3.0)
	# Expanding ping ring on the hovered sector.
	if _hover_idx >= 0 and _hover_idx < _nodes.size():
		var hp: Vector2 = _nodes[_hover_idx]["pos"]
		var hr := lerpf(NODE_R * 1.1, NODE_R * 2.7, _ping_t)
		draw_arc(hp, hr, 0.0, TAU, 36, Color(0.55, 0.92, 1.0, (1.0 - _ping_t) * 0.6), 2.0)
		# A connector line from the hovered node to the intel panel edge.
		if _intel and _intel.visible:
			draw_line(hp, Vector2(_intel.position.x, hp.y), Color(0.4, 0.8, 0.95, 0.25), 1.5)

func _hover_node(i: int) -> void:
	_hover_idx = i
	_ping_t = 0.0
	_set_intel(i)
	AudioBus.play_synth_ui("broadcast_blip", -17.0, 1.7)  # faint sonar tick on hover

func _unhover_node(i: int) -> void:
	if _hover_idx == i:
		_hover_idx = -1
		_set_intel(-1)

## Fill the intel panel for sector i (or the idle prompt when i == -1).
func _set_intel(i: int) -> void:
	if _intel_title == null:
		return
	if i < 0 or i >= _nodes.size():
		_intel_title.text = "SECTOR INTEL"
		_intel_act.text = ""
		_intel_body.text = "Hover a sector to pull its threat assessment.\n\nClick any reached sector to deploy. Red sectors are boss-held."
		return
	var d: Dictionary = _nodes[i]
	var locked: bool = i > _frontier
	var ci: int = d["chapter"]
	_intel_act.text = LevelDefs.chapter_name(ci)
	_intel_act.add_theme_color_override("font_color", _act_color(ci))
	if locked:
		_intel_title.text = "█ CLASSIFIED"
		_intel_title.add_theme_color_override("font_color", COL_LOCK)
		var threat := "\n☠ BOSS-HELD SECTOR" if d["boss"] else ""
		_intel_body.text = "Status: 🔒 LOCKED%s\n\nThreat assessment classified. Push the front line here to reveal hostiles and objective." % threat
		return
	_intel_title.text = "%d. %s" % [i + 1, d["title"]]
	_intel_title.add_theme_color_override("font_color", COL_BOSS if d["boss"] else Color(0.7, 0.95, 1.0))
	var def: Dictionary = LevelDefs.get_def(d["id"])
	var status: String = "▶ CURRENT OBJECTIVE" if i == _frontier else "✓ CLEARED"
	var lines := "Status: %s" % status
	if d["boss"]:
		lines += "\n☠ BOSS SECTOR"
	var obj: String = String(def.get("objective", ""))
	if obj != "":
		lines += "\n\nObjective:\n%s" % obj
	lines += "\n\nHostiles:\n%s" % _hostiles_of(d["id"])
	var best: String = str(GameState.level_bests.get(d["id"], ""))
	lines += "\n\nBest rank: %s" % ("★ %s" % best if best != "" else "—")
	_intel_body.text = lines

## A readable hostile roster for a sector: unique enemy types → codex names.
func _hostiles_of(id: String) -> String:
	var def: Dictionary = LevelDefs.get_def(id)
	var seen := {}
	var names: Array = []
	for e in def.get("enemies", []):
		var t := String((e as Dictionary).get("type", ""))
		if t == "" or seen.has(t):
			continue
		seen[t] = true
		names.append(String(EnemyCodex.get_entry(t).get("name", t.to_upper())) if EnemyCodex.has(t) else t.to_upper())
	if names.is_empty():
		return "No hostile signatures."
	if names.size() > 8:
		names = names.slice(0, 8)
		names.append("…")
	return ", ".join(names)

func _on_node_pressed(i: int) -> void:
	if i > _frontier:
		AudioBus.play_synth_ui("ui_deny", -6.0)
		return
	AudioBus.play_synth_ui("pickup_health", -6.0, 1.4)
	GameState.go_to_level(_campaign()[i])

func _on_back() -> void:
	AudioBus.play_synth_ui("ui_back", -8.0)
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
