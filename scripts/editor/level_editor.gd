extends Node3D
## In-game LEVEL EDITOR (dev tool). Edits a level def Dictionary (the same data
## LevelBuilder consumes) with a cheap marker preview, a hybrid top-down/free-fly
## camera, and load/save to res://dev_levels/*.lvl. Placement, gizmos, the
## inspector and campaign tools are layered on in later phases; this file owns the
## shared state (`def`, markers, camera, file ops) they build on.
##
## Run from source:  godot --path . res://scenes/editor/level_editor.tscn

# ---------- shared state ----------
var def: Dictionary = {}          # the level being edited (final world coords)
var current_name: String = "untitled"
var _markers: Array = []          # [{node, category, entry}] — entry is a live ref into `def`

var _camera: Camera3D
var _preview_root: Node3D
var _topdown := true
var _cam_target := Vector3.ZERO   # point the top-down camera orbits/pans around
var _cam_height := 38.0
var _cam_yaw := 0.0
var _fly_pos := Vector3(0, 8, 24)
var _fly_yaw := 0.0
var _fly_pitch := -0.4

# UI
var _status: Label
var _load_opt: OptionButton
var _name_edit: LineEdit
var _load_paths: Array = []       # parallel to _load_opt items
var _sel_label: Label
var _snap_btn: Button
var _insp_vb: VBoxContainer   # inspector body (rebuilt on selection / def change)

# ---------- placement / selection / transform (Phase 2) ----------
var _armed_category := ""         # palette item armed for placement ("" = select mode)
var _armed_item := ""
var _selection: Array = []        # selected marker records (subset of _markers)
var _gizmo: Node3D                 # visual axis cross at the selection

# Modal transform (Blender-style G/R/S): "", "move", "rotate", "scale".
var _mode := ""
var _mode_axis := ""              # "", "x", "y", "z"
var _mode_start := Vector3.ZERO   # cursor ground point at mode start
var _mode_orig := []              # snapshot: original {pos,yaw,size} per selected
var _dragging := false            # LMB free-drag move in progress

# Undo (snapshot stack) + clipboard.
var _undo: Array = []
var _redo: Array = []
var _clipboard: Array = []

# Snapping.
var _snap := true
var _grid := 1.0
var _angle_snap := 15.0

## category -> which def array placed entries append to.
const CAT_ARRAY := {
	"enemy": "enemies", "boss": "enemies", "prop": "props", "pickup": "pickups",
	"weapon": "extra_weapons", "light": "lights", "wall": "walls",
	"building": "buildings", "ramp": "ramps", "platform": "platforms",
	"hologram": "holograms", "fire": "fires",
}

# Category → marker tint.
const CAT_COLOR := {
	"enemy": Color(1.0, 0.3, 0.25), "boss": Color(1.0, 0.15, 0.3),
	"prop": Color(0.7, 0.7, 0.75), "weapon": Color(0.5, 0.8, 1.0),
	"pickup": Color(0.5, 1.0, 0.6), "light": Color(1.0, 0.9, 0.5),
	"building": Color(0.55, 0.57, 0.6), "wall": Color(0.5, 0.5, 0.55),
	"ramp": Color(0.6, 0.55, 0.45), "platform": Color(0.5, 0.6, 0.7),
	"hologram": Color(0.4, 0.8, 1.0), "fire": Color(1.0, 0.5, 0.2),
	"spawn": Color(0.3, 1.0, 0.4), "exit": Color(0.3, 0.8, 1.0),
	"hero": Color(0.6, 0.7, 1.0), "nexus": Color(1.0, 0.2, 0.15),
}

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if has_node("/root/GameState"):
		GameState.set_state(GameState.State.MENU)
	_build_environment()
	_build_camera()
	_build_ui()
	_preview_root = Node3D.new()
	add_child(_preview_root)
	_gizmo = _make_gizmo()
	add_child(_gizmo)
	_gizmo.visible = false
	set_def(blank_def())
	_refresh_load_list()
	set_process(true)
	set_process_unhandled_input(true)
	if "--editor-selftest" in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		_selftest.call_deferred()

## Headless smoke test (run: editor scene with --editor-selftest): load a built-in
## into the preview, save it, assert markers built + file written.
func _selftest() -> void:
	await get_tree().process_frame
	# Phase 1: build a built-in preview.
	var d := LevelDefs.get_def("gpt"); d["world_scale"] = 1.0
	set_def(d)
	await get_tree().process_frame
	var p1 := marker_count() > 0
	print("PHASE1 ", "PASS" if p1 else "FAIL", " markers=", marker_count())
	# Phase 2: place / move / duplicate / delete / undo / save on a blank level.
	set_def(blank_def())
	await get_tree().process_frame
	var base := marker_count() # spawn + exit
	_arm("enemy", "android")
	_place_at(Vector3(6, 0, 6))
	await get_tree().process_frame
	var ok_place := marker_count() == base + 1 and selection_count() == 1
	# Drag-move the placed enemy to (8,8).
	_drag_orig = _selection_positions()
	_drag_ref = _drag_orig[0]
	_drag_moved = true
	_drag_move_to(Vector3(8, 0, 8))
	var mp: Vector3 = def["enemies"][0]["pos"]
	var ok_move := is_equal_approx(mp.x, 8.0) and is_equal_approx(mp.z, 8.0)
	_duplicate_selection(); await get_tree().process_frame
	var ok_dup := (def["enemies"] as Array).size() == 2
	_delete_selection(); await get_tree().process_frame
	var ok_del := (def["enemies"] as Array).size() == 1
	_undo_do(); await get_tree().process_frame
	var ok_undo := (def["enemies"] as Array).size() == 2
	if _name_edit: _name_edit.text = "_selftest"
	_on_save()
	var saved := CustomLevels.load_def("res://dev_levels/_selftest.lvl")
	var ok_save := (saved.get("enemies", []) as Array).size() == 2
	var p2 := ok_place and ok_move and ok_dup and ok_del and ok_undo and ok_save
	print("P2 place=", ok_place, " move=", ok_move, " dup=", ok_dup, " del=", ok_del, " undo=", ok_undo, " save=", ok_save)
	print("PHASE2 ", "PASS" if p2 else "FAIL")
	# Phase 3: settings + env + tasks + export.
	def["name"] = "P3 Level"
	def["objective"] = "test obj"
	(def["env"] as Dictionary)["weather"] = "rain"
	(def["tasks"] as Array).append(_default_task("destroy_core"))
	var ok_tasks := (def["tasks"] as Array).size() >= 2
	_export_gdscript()
	var exp := CustomLevels.DIR + "_selftest_export.gd.txt"
	var exp_ok := FileAccess.file_exists(exp)
	var exp_txt := FileAccess.get_file_as_string(exp) if exp_ok else ""
	var exp_valid := "static func _" in exp_txt and "return {" in exp_txt
	_save_campaign(["res://scenes/levels/level_01.tscn", "res://dev_levels/_selftest.lvl"])
	var camp_ok := FileAccess.file_exists(CustomLevels.DIR + "campaign.json")
	var p3 := ok_tasks and exp_ok and exp_valid and camp_ok
	print("P3 tasks=", ok_tasks, " export=", exp_ok, " valid=", exp_valid, " campaign=", camp_ok)
	print("PHASE3 ", "PASS" if p3 else "FAIL")
	# Phase 4: validation + playtest save (don't actually change scene here).
	var warns := validate()
	var pt := CustomLevels.save_def(def, "_playtest")
	var p4 := pt != "" and FileAccess.file_exists("res://dev_levels/_playtest.lvl")
	print("P4 warns=", warns.size(), " playtest_save=", p4)
	print("PHASE4 ", "PASS" if p4 else "FAIL")
	get_tree().quit()

# ---------- def lifecycle ----------

static func blank_def() -> Dictionary:
	return {
		"name": "New Level",
		"objective": "Eliminate all hostiles and reach the exit",
		"open_sky": true,
		"floor_size": Vector2(40, 40),
		"floor_color": Color(0.18, 0.18, 0.2),
		"spawn": Vector3(-12, 1, -12),
		"exit": Vector3(12, 1.5, 12),
		"env": {
			"sky_top": Color(0.1, 0.11, 0.16), "sky_horizon": Color(0.3, 0.3, 0.35),
			"fog": Color(0.4, 0.42, 0.48), "fog_density": 0.01,
			"ambient": Color(0.5, 0.52, 0.6), "ambient_energy": 1.6,
			"sun_color": Color(0.96, 0.95, 0.92), "sun_energy": 1.4,
		},
		"enemies": [], "props": [], "buildings": [], "walls": [], "ramps": [],
		"platforms": [], "lights": [], "pickups": [], "holograms": [], "fires": [],
		"tasks": [{"type": "kill_all"}],
		"world_scale": 1.0,
	}

func set_def(d: Dictionary) -> void:
	def = d.duplicate(true)
	# Guarantee the arrays exist so placement code can append without checks.
	for k in ["enemies", "props", "buildings", "walls", "ramps", "platforms",
			"lights", "pickups", "holograms", "fires", "tasks"]:
		if not (def.get(k) is Array):
			def[k] = []
	if not (def.get("env") is Dictionary):
		def["env"] = {}
	_cam_target = Vector3(0, 0, 0)
	rebuild_preview()
	_refresh_inspector()
	_set_status("Loaded '%s'" % def.get("name", "level"))

# ---------- preview ----------

func rebuild_preview() -> void:
	for c in _preview_root.get_children():
		c.queue_free()
	_markers.clear()
	_build_floor_and_walls()
	# Singletons.
	_add_marker("spawn", def, "spawn")
	_add_marker("exit", def, "exit")
	if def.get("hero") is Dictionary:
		_add_marker("hero", def["hero"], "pos")
	if def.get("nexus") is Dictionary:
		_add_marker("nexus", def["nexus"], "pos")
	# Arrays.
	for e in def.get("enemies", []):
		_add_marker("boss" if _is_boss(e.get("type", "")) else "enemy", e, "pos")
	for e in def.get("props", []):
		_add_marker("prop", e, "pos")
	for e in def.get("pickups", []):
		_add_marker("pickup", e, "pos")
	for e in def.get("lights", []):
		_add_marker("light", e, "pos")
	for e in def.get("buildings", []):
		_add_marker("building", e, "pos")
	for e in def.get("walls", []):
		_add_marker("wall", e, "pos")
	for e in def.get("ramps", []):
		_add_marker("ramp", e, "pos")
	for e in def.get("platforms", []):
		_add_marker("platform", e, "pos")
	for e in def.get("holograms", []):
		_add_marker("hologram", e, "pos")
	for e in def.get("fires", []):
		_add_marker("fire", e, "pos")
	# Weapons (single + extra).
	if def.get("weapon") is Dictionary and not (def["weapon"] as Dictionary).is_empty():
		_add_marker("weapon", def["weapon"], "pos")
	for e in def.get("extra_weapons", []):
		_add_marker("weapon", e, "pos")

func _build_floor_and_walls() -> void:
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = fs
	floor_mi.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = def.get("floor_color", Color(0.18, 0.18, 0.2))
	floor_mi.material_override = fmat
	_preview_root.add_child(floor_mi)
	# Thin perimeter walls (visual bounds).
	var hx := fs.x * 0.5
	var hz := fs.y * 0.5
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.3, 0.31, 0.34)
	for w in [[Vector3(0, 1.5, -hz), Vector3(fs.x, 3, 0.4)], [Vector3(0, 1.5, hz), Vector3(fs.x, 3, 0.4)],
			[Vector3(-hx, 1.5, 0), Vector3(0.4, 3, fs.y)], [Vector3(hx, 1.5, 0), Vector3(0.4, 3, fs.y)]]:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = w[1]; b.mesh = bm
		b.material_override = wmat
		b.position = w[0]
		_preview_root.add_child(b)
	# Faint grid lines on the floor for placement reference.
	_build_grid(fs)

func _build_grid(fs: Vector2) -> void:
	var im := ImmediateMesh.new()
	var gm := MeshInstance3D.new()
	gm.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.4, 0.45, 0.5, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.material_override = mat
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var hx := fs.x * 0.5
	var hz := fs.y * 0.5
	var step := 2.0
	var x := -hx
	while x <= hx + 0.01:
		im.surface_add_vertex(Vector3(x, 0.02, -hz)); im.surface_add_vertex(Vector3(x, 0.02, hz))
		x += step
	var z := -hz
	while z <= hz + 0.01:
		im.surface_add_vertex(Vector3(-hx, 0.02, z)); im.surface_add_vertex(Vector3(hx, 0.02, z))
		z += step
	im.surface_end()
	_preview_root.add_child(gm)

## Build a marker for one entity and register it. `holder`/`key` say where its
## position lives so later phases can move it (holder[key] = new pos).
func _add_marker(category: String, holder: Dictionary, key: String) -> void:
	var pos: Vector3 = holder.get(key, Vector3.ZERO)
	var node := _make_marker_visual(category, holder)
	_preview_root.add_child(node)
	node.global_position = pos
	node.set_meta("category", category)
	node.set_meta("holder", holder)
	node.set_meta("key", key)
	_markers.append({"node": node, "category": category, "holder": holder, "key": key})

func _make_marker_visual(category: String, holder: Dictionary) -> Node3D:
	var root := Node3D.new()
	var col: Color = CAT_COLOR.get(category, Color.WHITE)
	match category:
		"wall", "building", "ramp", "platform":
			# Box sized to the entry's `size`.
			var size: Vector3 = holder.get("size", Vector3(2, 3, 2))
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new(); bm.size = size; mi.mesh = bm
			mi.material_override = _flat(col, 0.35)
			root.add_child(mi)
		"spawn", "exit":
			var mi := MeshInstance3D.new()
			var cyl := CylinderMesh.new(); cyl.top_radius = 0.0 if category == "spawn" else 0.6
			cyl.bottom_radius = 0.6; cyl.height = 1.6
			mi.mesh = cyl
			mi.material_override = _emis(col)
			mi.position.y = 0.8
			root.add_child(mi)
		_:
			# Default: a capsule/marker + a name label.
			var mi := MeshInstance3D.new()
			var cap := CapsuleMesh.new(); cap.radius = 0.4; cap.height = 1.6
			mi.mesh = cap
			mi.material_override = _emis(col)
			mi.position.y = 0.8
			root.add_child(mi)
	# Label.
	var lbl := Label3D.new()
	lbl.text = _marker_label(category, holder)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 48
	lbl.pixel_size = 0.01
	lbl.position.y = 2.4
	lbl.modulate = col
	lbl.outline_size = 8
	root.add_child(lbl)
	return root

func _marker_label(category: String, holder: Dictionary) -> String:
	match category:
		"enemy", "boss":
			return String(holder.get("type", "?")).to_upper()
		"prop":
			return String(holder.get("type", "prop"))
		"pickup":
			return String(holder.get("kind", "pickup"))
		"weapon":
			return String(holder.get("scene", "weapon")).get_file().get_basename()
		"spawn":
			return "SPAWN"
		"exit":
			return "EXIT"
		_:
			return category

func _flat(c: Color, a: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, a)
	if a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _emis(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.6
	return m

func _is_boss(t: String) -> bool:
	return t in ["terminator", "colossus", "overseer", "titan", "archon"]

# ---------- environment & camera ----------

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 1.0
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -40, 0)
	sun.light_energy = 1.0
	add_child(sun)

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.current = true
	_camera.far = 2000.0
	add_child(_camera)
	_apply_camera()

func _apply_camera() -> void:
	if _topdown:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		var p := _cam_target + Vector3(sin(_cam_yaw) * _cam_height * 0.15, _cam_height, cos(_cam_yaw) * _cam_height * 0.15)
		_camera.global_position = p
		_camera.look_at(_cam_target, Vector3.UP)
	else:
		var b := Basis.from_euler(Vector3(_fly_pitch, _fly_yaw, 0))
		_camera.global_transform = Transform3D(b, _fly_pos)

# ---------- input / camera control ----------

func _process(delta: float) -> void:
	if _mode != "":
		_update_transform_mode()
		return
	if _dragging and not _selection.is_empty():
		return # handled in mouse-motion
	if _topdown:
		var pan := Vector3.ZERO
		if Input.is_key_pressed(KEY_W): pan.z -= 1
		if Input.is_key_pressed(KEY_S): pan.z += 1
		if Input.is_key_pressed(KEY_A): pan.x -= 1
		if Input.is_key_pressed(KEY_D): pan.x += 1
		if pan != Vector3.ZERO:
			var sp := _cam_height * 0.6 * delta
			_cam_target += (Basis(Vector3.UP, _cam_yaw) * pan).normalized() * sp
			_apply_camera()
	else:
		var dir := Vector3.ZERO
		if Input.is_key_pressed(KEY_W): dir.z -= 1
		if Input.is_key_pressed(KEY_S): dir.z += 1
		if Input.is_key_pressed(KEY_A): dir.x -= 1
		if Input.is_key_pressed(KEY_D): dir.x += 1
		if Input.is_key_pressed(KEY_E): dir.y += 1
		if Input.is_key_pressed(KEY_Q): dir.y -= 1
		if dir != Vector3.ZERO:
			_fly_pos += _camera.global_transform.basis * dir.normalized() * 20.0 * delta
			_apply_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		if _mode != "":
			return # transform mode reads the cursor in _process
		# RMB drag rotates the camera (fly look / top-down yaw).
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			if _topdown:
				_cam_yaw += event.relative.x * 0.01
			else:
				_fly_yaw -= event.relative.x * 0.005
				_fly_pitch = clampf(_fly_pitch - event.relative.y * 0.005, -1.5, 1.5)
			_apply_camera()
		elif _dragging and not _selection.is_empty():
			_drag_move_to(_cursor_world())

func _handle_key(event: InputEventKey) -> void:
	if event.ctrl_pressed:
		match event.keycode:
			KEY_Z: _undo_do()
			KEY_Y: _redo_do()
			KEY_D: _duplicate_selection()
			KEY_C: _copy_selection()
			KEY_V: _paste_clipboard()
		return
	match event.keycode:
		KEY_TAB: _toggle_view()
		KEY_ESCAPE: _cancel_mode()
		KEY_DELETE, KEY_BACKSPACE: _delete_selection()
		KEY_G: _begin_mode("move")
		KEY_R: _begin_mode("rotate")
		KEY_F: _begin_mode("scale") # S is camera-back; F = scale ("form")
		KEY_X: _set_axis("x")
		KEY_Y: _set_axis("y")
		KEY_Z: _set_axis("z")

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and _dragging:
			_dragging = false
		return
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if _topdown: _cam_height = maxf(8.0, _cam_height - 3.0); _apply_camera()
		MOUSE_BUTTON_WHEEL_DOWN:
			if _topdown: _cam_height = minf(120.0, _cam_height + 3.0); _apply_camera()
		MOUSE_BUTTON_LEFT:
			if _mode != "":
				_confirm_mode() # click confirms an active grab/rotate/scale
				return
			if _armed_category != "":
				_place_at(_cursor_world())
			else:
				_click_select(event.shift_pressed)
		MOUSE_BUTTON_RIGHT:
			if _mode != "":
				_cancel_mode()

func _toggle_view() -> void:
	_topdown = not _topdown
	if not _topdown:
		# Drop the fly camera near where we were looking.
		_fly_pos = _cam_target + Vector3(0, 10, 20)
		_fly_yaw = 0.0
		_fly_pitch = -0.4
	_apply_camera()
	_set_status("View: %s" % ("TOP-DOWN" if _topdown else "FREE-FLY"))

# ---------- UI ----------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	layer.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	bar.add_child(hb)
	_add_btn(hb, "New", _on_new)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(160, 0)
	_name_edit.placeholder_text = "level name"
	_name_edit.text = current_name
	hb.add_child(_name_edit)
	_add_btn(hb, "Save", _on_save)
	_load_opt = OptionButton.new()
	_load_opt.custom_minimum_size = Vector2(220, 0)
	hb.add_child(_load_opt)
	_add_btn(hb, "Load", _on_load)
	_add_btn(hb, "View (Tab)", _toggle_view)
	_snap_btn = _add_btn(hb, "Snap: ON", _toggle_snap)
	_add_btn(hb, "Validate", _on_validate)
	var pt := _add_btn(hb, "▶ Playtest", _on_playtest)
	pt.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	var sep := VSeparator.new(); hb.add_child(sep)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	hb.add_child(_status)
	_build_palette(layer)
	_build_selection_panel(layer)
	_build_inspector(layer)

## Right-hand inspector: edits the selected entity, or (nothing selected) the
## level settings + env + tasks. Rebuilt by _refresh_inspector().
func _build_inspector(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.anchor_left = 1.0
	panel.offset_left = -300.0
	panel.offset_top = 44.0
	panel.offset_bottom = -104.0
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_insp_vb = VBoxContainer.new()
	_insp_vb.add_theme_constant_override("separation", 4)
	_insp_vb.custom_minimum_size = Vector2(284, 0)
	scroll.add_child(_insp_vb)

## Left-hand palette: category sections of placeable items. Clicking an item arms
## it for placement (click in the world to drop). "Select" disarms.
func _build_palette(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_top = 44.0
	panel.offset_bottom = -10.0
	panel.custom_minimum_size = Vector2(180, 0)
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	scroll.add_child(vb)
	var sel := Button.new()
	sel.text = "▣ SELECT / MOVE"
	sel.pressed.connect(func(): _arm("", ""))
	vb.add_child(sel)
	_palette_section(vb, "ENEMIES", "enemy", _enemy_items())
	_palette_section(vb, "BOSSES", "boss", ["terminator", "colossus", "overseer", "titan", "archon"])
	_palette_section(vb, "OBSTACLES", "prop", _prop_items())
	_palette_section(vb, "STRUCTURES", "", [])
	for s in ["wall", "building", "ramp", "platform"]:
		_palette_item(vb, s.to_upper(), s, s)
	_palette_section(vb, "WEAPONS", "weapon", _weapon_items())
	_palette_section(vb, "POWERUPS", "pickup", ["health", "ammo", "overclock", "overdrive"])
	_palette_section(vb, "LIGHTS / FX", "", [])
	for fx in [["light", "POINT LIGHT"], ["fire", "FIRE"], ["hologram", "HOLOGRAM"],
			["hero", "HERO MONOLITH"], ["nexus", "NEXUS TOWER"]]:
		_palette_item(vb, fx[1], fx[0], fx[0])

func _palette_section(vb: VBoxContainer, title: String, category: String, items: Array) -> void:
	var h := Label.new()
	h.text = "— %s —" % title
	h.add_theme_color_override("font_color", Color(0.55, 0.7, 0.95))
	h.add_theme_font_size_override("font_size", 12)
	vb.add_child(h)
	for it in items:
		_palette_item(vb, str(it).get_file().get_basename().to_upper(), category, str(it))

func _palette_item(vb: VBoxContainer, label: String, category: String, item: String) -> void:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(168, 26)
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(func(): _arm(category, item))
	vb.add_child(b)

func _enemy_items() -> Array:
	var out: Array = []
	for k in LevelBuilder.ENEMY_SCENES.keys():
		if not _is_boss(k):
			out.append(k)
	out.sort()
	return out

func _prop_items() -> Array:
	var out: Array = LevelBuilder.PROP_SCENES.keys()
	out.sort()
	return out

func _weapon_items() -> Array:
	return GameState.ALL_WEAPONS + ["res://scenes/weapons/sniper.tscn", "res://scenes/weapons/magnum.tscn"]

## Bottom-right: what's selected + quick actions/help.
func _build_selection_panel(layer: CanvasLayer) -> void:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	p.anchor_left = 1.0; p.anchor_top = 1.0
	p.offset_left = -360.0; p.offset_top = -96.0
	p.offset_right = -8.0; p.offset_bottom = -8.0
	layer.add_child(p)
	_sel_label = Label.new()
	_sel_label.add_theme_font_size_override("font_size", 13)
	_sel_label.text = _help_text()
	p.add_child(_sel_label)

func _help_text() -> String:
	return "LMB place/select · drag move · G/R/S grab/rot/scale (X/Y/Z axis) · Del · Ctrl+D dup · Ctrl+C/V · Ctrl+Z/Y · Tab view"

func _toggle_snap() -> void:
	_snap = not _snap
	if _snap_btn: _snap_btn.text = "Snap: %s" % ("ON" if _snap else "OFF")

func _add_btn(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _set_status(s: String) -> void:
	if _status:
		_status.text = s

func _refresh_load_list() -> void:
	if _load_opt == null:
		return
	_load_opt.clear()
	_load_paths.clear()
	# Built-in campaign levels (editable copies).
	for id in _builtin_ids():
		_load_opt.add_item("built-in: %s" % id)
		_load_paths.append({"builtin": id})
	# Saved custom levels.
	for p in CustomLevels.list_paths():
		_load_opt.add_item("file: %s" % CustomLevels.name_of(p))
		_load_paths.append({"path": p})

func _builtin_ids() -> Array:
	# Mirror LevelDefs._defs() keys (campaign + sandbox), minus none.
	return ["01", "gpt", "gemini", "claude", "grok", "suburb", "suburb_boss",
		"mistral", "overseer", "alien", "uplink", "assembly", "titan", "archon",
		"crucible", "frostbreak", "neon"]

# ---------- file ops ----------

func _on_new() -> void:
	current_name = "untitled"
	if _name_edit: _name_edit.text = current_name
	set_def(blank_def())

func _on_save() -> void:
	if _name_edit and _name_edit.text.strip_edges() != "":
		current_name = _name_edit.text.strip_edges()
	def["name"] = def.get("name", current_name)
	var p := CustomLevels.save_def(def, current_name)
	_refresh_load_list()
	_set_status("Saved %s" % p if p != "" else "SAVE FAILED")

func _on_load() -> void:
	if _load_opt == null or _load_opt.selected < 0 or _load_opt.selected >= _load_paths.size():
		return
	var sel: Dictionary = _load_paths[_load_opt.selected]
	if sel.has("builtin"):
		var d := LevelDefs.get_def(sel["builtin"])
		d["world_scale"] = 1.0 # editor works in final coords; don't re-scale on play
		current_name = "copy_of_%s" % sel["builtin"]
		set_def(d)
	else:
		current_name = CustomLevels.name_of(sel["path"])
		set_def(CustomLevels.load_def(sel["path"]))
	if _name_edit: _name_edit.text = current_name

# ---------- placement / selection / transform (Phase 2) ----------

func _arm(category: String, item: String) -> void:
	_armed_category = category
	_armed_item = item
	if category != "":
		_set_selection([])
	_set_status("Armed: %s %s" % [category, item] if category != "" else "Select / Move mode")

func _ray() -> Array:
	var mp := get_viewport().get_mouse_position()
	return [_camera.project_ray_origin(mp), _camera.project_ray_normal(mp)]

## Cursor projected onto the ground plane (y=0).
func _cursor_world() -> Vector3:
	var r := _ray()
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	if absf(d.y) < 1e-5:
		return _cam_target
	var t := -o.y / d.y
	if t < 0.0:
		return _cam_target
	return o + d * t

func _snap_pos(v: Vector3) -> Vector3:
	if not _snap:
		return v
	return Vector3(round(v.x / _grid) * _grid, v.y, round(v.z / _grid) * _grid)

func _snap_deg(a: float) -> float:
	if not _snap:
		return a
	return round(a / _angle_snap) * _angle_snap

func _pick_marker():
	var r := _ray()
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	var best = null
	var best_dist := 1e9
	for m in _markers:
		var p: Vector3 = m["node"].global_position + Vector3(0, 0.8, 0)
		var t: float = (p - o).dot(d)
		if t < 0.0:
			continue
		var dist: float = (o + d * t).distance_to(p)
		if dist < maxf(1.5, t * 0.06) and dist < best_dist:
			best_dist = dist
			best = m
	return best

func _click_select(additive: bool) -> void:
	var m = _pick_marker()
	if m == null:
		if not additive:
			_set_selection([])
		return
	if additive:
		if m in _selection:
			_selection.erase(m)
		else:
			_selection.append(m)
		_set_selection(_selection)
	else:
		_set_selection([m])
		# Arm a drag-move; only commits to undo if the cursor actually moves.
		_dragging = true
		_pending_undo = def.duplicate(true)
		_drag_ref = _cursor_world()
		_drag_orig = _selection_positions()
		_drag_moved = false

var _pending_undo: Variant = null
var _drag_ref := Vector3.ZERO
var _drag_orig: Array = []
var _drag_moved := false

func _selection_positions() -> Array:
	var out: Array = []
	for m in _selection:
		out.append((m["holder"] as Dictionary).get(m["key"], Vector3.ZERO))
	return out

func _drag_move_to(world: Vector3) -> void:
	if _selection.is_empty():
		return
	if not _drag_moved:
		if _pending_undo != null:
			_undo.append(_pending_undo)
			_redo.clear()
		_drag_moved = true
	var delta := world - _drag_ref
	for i in _selection.size():
		var m: Dictionary = _selection[i]
		var np: Vector3 = _snap_pos((_drag_orig[i] as Vector3) + delta)
		np.y = (_drag_orig[i] as Vector3).y
		(m["holder"] as Dictionary)[m["key"]] = np
		m["node"].global_position = np
	_update_gizmo()

# --- placement ---

func _place_at(world: Vector3) -> void:
	if _armed_category == "":
		return
	_push_undo()
	var entry := _default_entry(_armed_category, _armed_item, _snap_pos(world))
	if _armed_category in CAT_ARRAY:
		(def[CAT_ARRAY[_armed_category]] as Array).append(entry)
	elif _armed_category in ["hero", "nexus"]:
		def[_armed_category] = entry
	rebuild_preview()
	_select_holders([entry])
	_set_status("Placed %s" % _armed_item)

func _default_entry(cat: String, item: String, pos: Vector3) -> Dictionary:
	match cat:
		"enemy", "boss": return {"type": item, "pos": pos}
		"prop": return {"type": item, "pos": pos, "yaw": 0.0}
		"pickup": return {"kind": item, "pos": pos}
		"weapon": return {"scene": item, "pos": pos, "color": Color(0.5, 0.8, 1.0)}
		"light": return {"pos": pos + Vector3(0, 5, 0), "color": Color(1, 0.9, 0.7), "energy": 2.0, "range": 14.0}
		"wall": return {"pos": pos + Vector3(0, 1.5, 0), "size": Vector3(4, 3, 1)}
		"building": return {"pos": pos + Vector3(0, 2.5, 0), "size": Vector3(8, 5, 8)}
		"ramp": return {"pos": pos + Vector3(0, 1, 0), "size": Vector3(4, 0.5, 8), "pitch": 22.0, "yaw": 0.0}
		"platform": return {"pos": pos + Vector3(0, 1.5, 0), "size": Vector3(6, 3, 6)}
		"hologram": return {"pos": pos, "text": "OCCUPIED ZONE", "color": Color(0.4, 0.8, 1.0)}
		"fire": return {"pos": pos, "scale": 1.0}
		"hero": return {"pos": pos, "color": Color(0.6, 0.7, 1.0), "height": 5.0}
		"nexus": return {"pos": pos, "height": 16.0, "color": Color(1.0, 0.16, 0.12)}
	return {"pos": pos}

# --- modal transform (G/R/F + X/Y/Z) ---

var _mode_mouse_start := Vector2.ZERO

func _begin_mode(mode: String) -> void:
	if _selection.is_empty() or _armed_category != "":
		return
	_push_undo()
	_mode = mode
	_mode_axis = ""
	_mode_start = _cursor_world()
	_mode_mouse_start = get_viewport().get_mouse_position()
	_mode_orig.clear()
	for m in _selection:
		var h: Dictionary = m["holder"]
		_mode_orig.append({"pos": h.get(m["key"], Vector3.ZERO), "yaw": h.get("yaw", 0.0), "size": h.get("size", Vector3.ONE)})
	_set_status("%s  (X/Y/Z axis · click confirm · Esc cancel)" % mode.to_upper())

func _set_axis(a: String) -> void:
	if _mode == "":
		return
	_mode_axis = "" if _mode_axis == a else a

func _update_transform_mode() -> void:
	match _mode:
		"move":
			var delta := _cursor_world() - _mode_start
			if _mode_axis == "x": delta = Vector3(delta.x, 0, 0)
			elif _mode_axis == "z": delta = Vector3(0, 0, delta.z)
			elif _mode_axis == "y": delta = Vector3.ZERO # Y via inspector
			for i in _selection.size():
				var m: Dictionary = _selection[i]
				var np: Vector3 = _snap_pos((_mode_orig[i]["pos"] as Vector3) + delta)
				np.y = (_mode_orig[i]["pos"] as Vector3).y
				(m["holder"] as Dictionary)[m["key"]] = np
				m["node"].global_position = np
		"rotate":
			var dx := get_viewport().get_mouse_position().x - _mode_mouse_start.x
			var yaw := _snap_deg((_mode_orig[0]["yaw"] as float) + dx * 0.5)
			for i in _selection.size():
				var m: Dictionary = _selection[i]
				(m["holder"] as Dictionary)["yaw"] = yaw
				m["node"].rotation.y = deg_to_rad(yaw)
		"scale":
			var dy := _mode_mouse_start.y - get_viewport().get_mouse_position().y
			var f: float = clampf(1.0 + dy * 0.01, 0.2, 6.0)
			for i in _selection.size():
				var m: Dictionary = _selection[i]
				if not (m["holder"] as Dictionary).has("size"):
					continue
				var sz: Vector3 = (_mode_orig[i]["size"] as Vector3) * f
				if _snap:
					sz = Vector3(round(sz.x * 2) / 2.0, round(sz.y * 2) / 2.0, round(sz.z * 2) / 2.0)
				(m["holder"] as Dictionary)["size"] = sz
			rebuild_preview() # size change rebuilds the box marker
			_select_holders(_selection_holders())
	_update_gizmo()

func _confirm_mode() -> void:
	_mode = ""
	_mode_axis = ""
	_set_status("OK")

func _cancel_mode() -> void:
	if _mode == "":
		return
	# Restore originals and discard the undo snapshot we pushed at begin.
	for i in _selection.size():
		var m: Dictionary = _selection[i]
		var h: Dictionary = m["holder"]
		h[m["key"]] = _mode_orig[i]["pos"]
		h["yaw"] = _mode_orig[i]["yaw"]
		if h.has("size"):
			h["size"] = _mode_orig[i]["size"]
	if not _undo.is_empty():
		_undo.pop_back()
	_mode = ""
	_mode_axis = ""
	rebuild_preview()
	_select_holders(_selection_holders())
	_set_status("Cancelled")

# --- delete / duplicate / clipboard ---

func _delete_selection() -> void:
	if _selection.is_empty():
		return
	_push_undo()
	for m in _selection:
		_remove_holder(m["holder"], m["category"])
	_set_selection([])
	rebuild_preview()
	_set_status("Deleted")

func _remove_holder(holder: Dictionary, category: String) -> void:
	if category in ["spawn", "exit"]:
		return # required singletons — can't delete
	for k in ["hero", "nexus", "weapon"]:
		if def.get(k) is Dictionary and is_same(def[k], holder):
			def.erase(k)
			return
	for arr in CAT_ARRAY.values():
		var a: Array = def.get(arr, [])
		for i in a.size():
			if is_same(a[i], holder):
				a.remove_at(i)
				return

func _duplicate_selection() -> void:
	if _selection.is_empty():
		return
	_push_undo()
	var made: Array = []
	for m in _selection:
		var cat: String = m["category"]
		if cat in ["spawn", "exit", "hero", "nexus"]:
			continue
		var arr_name: String = CAT_ARRAY.get(cat, "")
		if arr_name == "":
			continue
		var copy: Dictionary = (m["holder"] as Dictionary).duplicate(true)
		copy["pos"] = (copy.get("pos", Vector3.ZERO) as Vector3) + Vector3(2, 0, 2)
		(def[arr_name] as Array).append(copy)
		made.append(copy)
	rebuild_preview()
	_select_holders(made)
	_set_status("Duplicated %d" % made.size())

func _copy_selection() -> void:
	_clipboard.clear()
	for m in _selection:
		if m["category"] in ["spawn", "exit"]:
			continue
		_clipboard.append({"category": m["category"], "entry": (m["holder"] as Dictionary).duplicate(true)})
	_set_status("Copied %d" % _clipboard.size())

func _paste_clipboard() -> void:
	if _clipboard.is_empty():
		return
	_push_undo()
	var made: Array = []
	for c in _clipboard:
		var cat: String = c["category"]
		var copy: Dictionary = (c["entry"] as Dictionary).duplicate(true)
		copy["pos"] = (copy.get("pos", Vector3.ZERO) as Vector3) + Vector3(2, 0, 2)
		if cat in CAT_ARRAY:
			(def[CAT_ARRAY[cat]] as Array).append(copy)
			made.append(copy)
		elif cat in ["hero", "nexus"]:
			def[cat] = copy
			made.append(copy)
	rebuild_preview()
	_select_holders(made)
	_set_status("Pasted %d" % made.size())

# --- undo / redo ---

func _push_undo() -> void:
	_undo.append(def.duplicate(true))
	if _undo.size() > 60:
		_undo.pop_front()
	_redo.clear()

func _undo_do() -> void:
	if _undo.is_empty():
		return
	_redo.append(def.duplicate(true))
	def = _undo.pop_back()
	_set_selection([])
	rebuild_preview()
	_set_status("Undo")

func _redo_do() -> void:
	if _redo.is_empty():
		return
	_undo.append(def.duplicate(true))
	def = _redo.pop_back()
	_set_selection([])
	rebuild_preview()
	_set_status("Redo")

# --- selection state / gizmo ---

func _selection_holders() -> Array:
	var out: Array = []
	for m in _selection:
		out.append(m["holder"])
	return out

func _set_selection(list: Array) -> void:
	_selection = list.duplicate()
	# Highlight: brighten selected markers' labels.
	for m in _markers:
		var on: bool = m in _selection
		for c in m["node"].get_children():
			if c is Label3D:
				(c as Label3D).outline_size = 16 if on else 8
				(c as Label3D).modulate = Color(1, 1, 0.4) if on else CAT_COLOR.get(m["category"], Color.WHITE)
	_update_gizmo()
	if _selection.is_empty():
		_set_status("—")
	elif _selection.size() == 1:
		_set_status("Selected: %s" % _marker_label(_selection[0]["category"], _selection[0]["holder"]))
	else:
		_set_status("Selected: %d objects" % _selection.size())
	_refresh_inspector()

## Re-select markers by their underlying entry dicts (after a rebuild relinks them).
func _select_holders(holders: Array) -> void:
	var found: Array = []
	for m in _markers:
		for h in holders:
			if is_same(m["holder"], h):
				found.append(m)
				break
	_set_selection(found)

func _update_gizmo() -> void:
	if _gizmo == null:
		return
	if _selection.is_empty():
		_gizmo.visible = false
		return
	var c := Vector3.ZERO
	for m in _selection:
		c += m["node"].global_position
	c /= _selection.size()
	_gizmo.global_position = c + Vector3(0, 0.8, 0)
	_gizmo.visible = true

func _make_gizmo() -> Node3D:
	var root := Node3D.new()
	for spec in [["x", Color(1, 0.3, 0.3)], ["y", Color(0.3, 1, 0.3)], ["z", Color(0.45, 0.55, 1)]]:
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.05; cyl.bottom_radius = 0.05; cyl.height = 2.2
		mi.mesh = cyl
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = spec[1]; m.emission_enabled = true; m.emission = spec[1]
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		match spec[0]:
			"x": mi.rotation_degrees = Vector3(0, 0, -90); mi.position = Vector3(1.1, 0, 0)
			"y": mi.position = Vector3(0, 1.1, 0)
			"z": mi.rotation_degrees = Vector3(90, 0, 0); mi.position = Vector3(0, 0, 1.1)
		root.add_child(mi)
	return root

# ---------- inspector / level settings / tasks (Phase 3) ----------

var _editing := false # suppress inspector rebuild while typing in a field

const ENV_COLORS := ["sky_top", "sky_horizon", "ground", "fog", "ambient", "sun_color", "building_tint"]
const ENV_NUMS := {
	"fog_density": [0.0, 0.05, 0.001], "ambient_energy": [0.0, 6.0, 0.1],
	"sun_energy": [0.0, 6.0, 0.1], "glow": [0.0, 2.0, 0.05],
	"brightness": [0.5, 1.5, 0.02], "contrast": [0.5, 1.8, 0.02],
	"saturation": [0.0, 2.0, 0.02], "sky_energy": [0.0, 4.0, 0.1],
}
const TASK_TYPES := ["kill_all", "key", "destroy_core", "collect_shards",
	"hack_terminal", "sabotage", "survive", "hold_zone"]

func _refresh_inspector() -> void:
	if _editing or _insp_vb == null:
		return
	for c in _insp_vb.get_children():
		c.queue_free()
	if _selection.size() == 1:
		_inspect_entity(_selection[0])
	elif _selection.size() > 1:
		_insp_header("%d objects selected" % _selection.size())
		_insp_btn("Delete all", _delete_selection)
	else:
		_inspect_level()

func _insp_header(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	l.add_theme_font_size_override("font_size", 15)
	_insp_vb.add_child(l)

func _insp_btn(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	_insp_vb.add_child(b)

func _row(label: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(96, 0)
	l.add_theme_font_size_override("font_size", 12)
	hb.add_child(l)
	_insp_vb.add_child(hb)
	return hb

func _live() -> void:
	# Rebuild markers to reflect an edit, keep the same selection, don't rebuild
	# the inspector (so the widget being edited keeps focus).
	var holders := _selection_holders()
	_editing = true
	rebuild_preview()
	_select_holders(holders)
	_editing = false

func _f_text(holder: Dictionary, key: String, label: String) -> void:
	var hb := _row(label)
	var le := LineEdit.new()
	le.text = str(holder.get(key, ""))
	le.custom_minimum_size = Vector2(170, 0)
	le.text_changed.connect(func(t): holder[key] = t)
	hb.add_child(le)

func _f_num(holder: Dictionary, key: String, label: String, mn: float, mx: float, step: float, do_live := false) -> void:
	var hb := _row(label)
	var sb := SpinBox.new()
	sb.min_value = mn; sb.max_value = mx; sb.step = step
	sb.value = float(holder.get(key, 0.0))
	sb.custom_minimum_size = Vector2(120, 0)
	sb.value_changed.connect(func(v):
		holder[key] = v
		if do_live: _live())
	hb.add_child(sb)

func _f_vec(holder: Dictionary, key: String, label: String, dims: int) -> void:
	var hb := _row(label)
	var cur = holder.get(key, Vector3.ZERO if dims == 3 else Vector2.ZERO)
	for i in dims:
		var sb := SpinBox.new()
		sb.min_value = -300; sb.max_value = 300; sb.step = 0.5
		sb.custom_minimum_size = Vector2(56, 0)
		sb.value = cur[i]
		var idx := i
		sb.value_changed.connect(func(v):
			var c = holder.get(key, Vector3.ZERO if dims == 3 else Vector2.ZERO)
			c[idx] = v
			holder[key] = c
			_live())
		hb.add_child(sb)

func _f_color(holder: Dictionary, key: String, label: String) -> void:
	var hb := _row(label)
	var cp := ColorPickerButton.new()
	cp.color = holder.get(key, Color.WHITE)
	cp.custom_minimum_size = Vector2(120, 24)
	cp.color_changed.connect(func(c): holder[key] = c)
	hb.add_child(cp)

func _f_bool(holder: Dictionary, key: String, label: String) -> void:
	var hb := _row(label)
	var cb := CheckBox.new()
	cb.button_pressed = bool(holder.get(key, false))
	cb.toggled.connect(func(p): holder[key] = p; _live())
	hb.add_child(cb)

func _f_enum(holder: Dictionary, key: String, label: String, options: Array) -> void:
	var hb := _row(label)
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(170, 0)
	var cur := str(holder.get(key, options[0] if not options.is_empty() else ""))
	for i in options.size():
		opt.add_item(str(options[i]).get_file().get_basename())
		if str(options[i]) == cur:
			opt.select(i)
	opt.item_selected.connect(func(i):
		holder[key] = options[i]
		_live())
	hb.add_child(opt)

func _inspect_entity(m: Dictionary) -> void:
	var cat: String = m["category"]
	var h: Dictionary = m["holder"]
	_insp_header(cat.to_upper())
	_f_vec(h, m["key"], "pos", 3)
	match cat:
		"enemy", "boss":
			_f_enum(h, "type", "type", LevelBuilder.ENEMY_SCENES.keys())
			_f_num(h, "count", "count", 1, 30, 1)
			_f_num(h, "trigger", "trigger r", 0, 60, 1)
		"prop":
			_f_enum(h, "type", "type", LevelBuilder.PROP_SCENES.keys())
			_f_num(h, "yaw", "yaw", -180, 180, 5)
		"pickup":
			_f_enum(h, "kind", "kind", ["health", "ammo", "overclock", "overdrive"])
		"weapon":
			_f_enum(h, "scene", "weapon", _weapon_items())
			_f_color(h, "color", "glow")
		"light":
			_f_color(h, "color", "color")
			_f_num(h, "energy", "energy", 0, 8, 0.1)
			_f_num(h, "range", "range", 2, 40, 1)
			_f_bool(h, "flicker", "flicker")
		"wall", "building", "platform":
			_f_vec(h, "size", "size", 3)
		"ramp":
			_f_vec(h, "size", "size", 3)
			_f_num(h, "pitch", "pitch", 0, 60, 2)
			_f_num(h, "yaw", "yaw", -180, 180, 5)
		"hologram":
			_f_text(h, "text", "text")
			_f_color(h, "color", "color")
		"fire":
			_f_num(h, "scale", "scale", 0.3, 3, 0.1)
		"hero", "nexus":
			_f_color(h, "color", "color")
			_f_num(h, "height", "height", 3, 24, 0.5)
	if cat not in ["spawn", "exit"]:
		_insp_btn("Delete", _delete_selection)

func _inspect_level() -> void:
	_insp_header("LEVEL SETTINGS")
	_f_text(def, "name", "name")
	_f_text(def, "objective", "objective")
	_f_text(def, "sign", "sign")
	_f_bool(def, "open_sky", "open sky")
	_f_vec(def, "floor_size", "floor size", 2)
	_f_color(def, "floor_color", "floor col")
	# Environment (full manual control).
	_insp_header("ENVIRONMENT")
	var env: Dictionary = def["env"]
	for k in ENV_COLORS:
		if not env.has(k): env[k] = Color(0.3, 0.3, 0.35)
		_f_color(env, k, k)
	for k in ENV_NUMS:
		if not env.has(k): env[k] = 1.0
		var spec: Array = ENV_NUMS[k]
		_f_num(env, k, k, spec[0], spec[1], spec[2])
	_f_enum(env, "weather", "weather", ["", "rain", "dust"])
	_f_bool(env, "lightning", "lightning")
	_f_bool(env, "stars", "stars")
	_f_enum(env, "hdri", "hdri", ["", "res://assets/environments/hdri/industrial_sunset_puresky_2k.hdr",
		"res://assets/environments/hdri/kloppenheim_06_puresky_2k.hdr"])
	# Tasks.
	_insp_header("OBJECTIVES / TASKS")
	_build_tasks_editor()
	# Tools.
	_insp_header("TOOLS")
	_insp_btn("Export to GDScript", _export_gdscript)
	_insp_btn("Campaign manager…", _open_campaign)

func _build_tasks_editor() -> void:
	var tasks: Array = def.get("tasks", [])
	for i in tasks.size():
		var t: Dictionary = tasks[i]
		var idx := i
		var hb := _row("• %s" % t.get("type", "?"))
		var opt := OptionButton.new()
		for j in TASK_TYPES.size():
			opt.add_item(TASK_TYPES[j])
			if TASK_TYPES[j] == t.get("type", ""):
				opt.select(j)
		opt.item_selected.connect(func(j):
			tasks[idx] = _default_task(TASK_TYPES[j])
			_refresh_inspector())
		hb.add_child(opt)
		var rm := Button.new(); rm.text = "✕"
		rm.pressed.connect(func(): tasks.remove_at(idx); _refresh_inspector())
		hb.add_child(rm)
		# Per-type fields.
		match t.get("type", ""):
			"key", "destroy_core", "hack_terminal", "sabotage", "hold_zone":
				_f_vec(t, "pos", "  pos", 3)
		match t.get("type", ""):
			"destroy_core":
				_f_num(t, "health", "  health", 100, 4000, 50)
			"survive", "hack_terminal", "sabotage", "hold_zone":
				_f_num(t, "seconds", "  seconds", 1, 120, 1)
	_insp_btn("+ Add task", func(): (def["tasks"] as Array).append(_default_task("kill_all")); _refresh_inspector())

func _default_task(type: String) -> Dictionary:
	match type:
		"key": return {"type": "key", "pos": Vector3.ZERO}
		"destroy_core": return {"type": "destroy_core", "pos": Vector3.ZERO, "health": 600.0}
		"collect_shards": return {"type": "collect_shards", "points": [Vector3.ZERO]}
		"hack_terminal": return {"type": "hack_terminal", "pos": Vector3.ZERO, "seconds": 3.0}
		"sabotage": return {"type": "sabotage", "pos": Vector3.ZERO, "seconds": 3.5}
		"survive": return {"type": "survive", "seconds": 45.0}
		"hold_zone": return {"type": "hold_zone", "pos": Vector3.ZERO, "seconds": 12.0}
	return {"type": "kill_all"}

# ---------- export to GDScript ----------

func _export_gdscript() -> void:
	var id := current_name.to_lower().replace(" ", "_")
	var text := _gdscript_for(def, id)
	var path := CustomLevels.DIR + id + "_export.gd.txt"
	CustomLevels._ensure(CustomLevels.DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		path = CustomLevels.USER_DIR + id + "_export.gd.txt"
		CustomLevels._ensure(CustomLevels.USER_DIR)
		f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
		_set_status("Exported GDScript -> %s" % path)
	else:
		_set_status("Export failed")

## Render the def as a LevelDefs static-func body (final coords; world_scale 1.0
## so paste-in matches editor placement — add to level_defs.gd & _defs()).
func _gdscript_for(d: Dictionary, id: String) -> String:
	var s := "## Paste into level_defs.gd and add \"%s\": _%s() to _defs().\n" % [id, id]
	s += "static func _%s() -> Dictionary:\n\treturn {\n" % id
	var keys := d.keys()
	keys.sort()
	for k in keys:
		if k in ["world_scale", "format_version"]:
			continue
		s += "\t\t%s: %s,\n" % [var_to_str(k), _gd_value(d[k])]
	s += "\t}\n"
	return s

func _gd_value(v) -> String:
	# var_to_str already emits valid GDScript literals for our value types
	# (Vector2/3, Color, Dictionary, Array, numbers, strings).
	return var_to_str(v)

# ---------- campaign manager ----------

var _campaign_win: Window

func _open_campaign() -> void:
	if _campaign_win and is_instance_valid(_campaign_win):
		_campaign_win.queue_free()
	_campaign_win = Window.new()
	_campaign_win.title = "Campaign Manager"
	_campaign_win.size = Vector2i(520, 560)
	_campaign_win.close_requested.connect(func(): _campaign_win.queue_free())
	add_child(_campaign_win)
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_campaign_win.add_child(sc)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(500, 0)
	sc.add_child(vb)
	_render_campaign(vb)
	_campaign_win.popup_centered()

func _render_campaign(vb: VBoxContainer) -> void:
	for c in vb.get_children():
		c.queue_free()
	var list := _campaign_list()
	var lbl := Label.new()
	lbl.text = "Campaign order (saved to dev_levels/campaign.json):"
	vb.add_child(lbl)
	for i in list.size():
		var idx := i
		var hb := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = "%d. %s" % [i + 1, str(list[i]).get_file()]
		name_lbl.custom_minimum_size = Vector2(300, 0)
		hb.add_child(name_lbl)
		_mini_btn(hb, "↑", func(): _campaign_move(idx, -1, vb))
		_mini_btn(hb, "↓", func(): _campaign_move(idx, 1, vb))
		_mini_btn(hb, "✕", func(): _campaign_remove(idx, vb))
		vb.add_child(hb)
	# Add current custom levels.
	var add_lbl := Label.new(); add_lbl.text = "Add a level:"; vb.add_child(add_lbl)
	for p in CustomLevels.list_paths():
		var path: String = p
		_mini_full(vb, "+ %s" % CustomLevels.name_of(path), func(): _campaign_add(path, vb))
	_mini_full(vb, "💾 Save campaign.json", func(): _save_campaign(_campaign_list()))

func _mini_btn(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new(); b.text = text; b.pressed.connect(cb); parent.add_child(b)

func _mini_full(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new(); b.text = text; b.pressed.connect(cb); parent.add_child(b)

var _campaign_cache: Array = []

func _campaign_list() -> Array:
	if _campaign_cache.is_empty():
		var p := CustomLevels.DIR + "campaign.json"
		if FileAccess.file_exists(p):
			var v = JSON.parse_string(FileAccess.get_file_as_string(p))
			if v is Array:
				_campaign_cache = v
		if _campaign_cache.is_empty() and has_node("/root/GameState"):
			_campaign_cache = (GameState.CAMPAIGN as Array).duplicate()
	return _campaign_cache

func _campaign_move(i: int, dir: int, vb: VBoxContainer) -> void:
	var j := i + dir
	if j < 0 or j >= _campaign_cache.size():
		return
	var tmp = _campaign_cache[i]; _campaign_cache[i] = _campaign_cache[j]; _campaign_cache[j] = tmp
	_render_campaign(vb)

func _campaign_remove(i: int, vb: VBoxContainer) -> void:
	_campaign_cache.remove_at(i)
	_render_campaign(vb)

func _campaign_add(path: String, vb: VBoxContainer) -> void:
	_campaign_cache.append(path)
	_render_campaign(vb)

func _save_campaign(list: Array) -> void:
	CustomLevels._ensure(CustomLevels.DIR)
	var f := FileAccess.open(CustomLevels.DIR + "campaign.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(list, "\t"))
		f.close()
		_set_status("Saved campaign.json (%d levels)" % list.size())

# ---------- validation + playtest (Phase 4) ----------

## Non-blocking sanity checks. Returns a list of human-readable warnings.
func validate() -> Array:
	var w: Array = []
	if not def.has("spawn"):
		w.append("no spawn point")
	if not def.has("exit"):
		w.append("no exit")
	var enemies: Array = def.get("enemies", [])
	var tasks: Array = def.get("tasks", [])
	if not enemies.is_empty() and tasks.is_empty():
		w.append("enemies but no objective")
	for t in tasks:
		var ty: String = t.get("type", "")
		if ty in ["destroy_core", "hold_zone", "key", "hack_terminal", "sabotage"] and not t.has("pos"):
			w.append("%s task missing pos" % ty)
		if ty == "collect_shards" and (t.get("points", []) as Array).is_empty():
			w.append("collect_shards has no points")
	# Out-of-bounds spawn/exit.
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	for k in ["spawn", "exit"]:
		var p: Vector3 = def.get(k, Vector3.ZERO)
		if absf(p.x) > fs.x * 0.5 + 1.0 or absf(p.z) > fs.y * 0.5 + 1.0:
			w.append("%s is outside the floor" % k)
	return w

func _on_validate() -> void:
	var w := validate()
	_set_status("✓ No issues" if w.is_empty() else "⚠ " + ", ".join(w))

func _on_playtest() -> void:
	var w := validate()
	if not w.is_empty():
		_set_status("⚠ " + ", ".join(w) + "  (playing anyway)")
	var p := CustomLevels.save_def(def, "_playtest")
	if p == "":
		_set_status("Playtest failed: could not save")
		return
	if has_node("/root/GameState"):
		GameState.custom_level_path = p
		GameState.set_state(GameState.State.PLAYING)
	get_tree().change_scene_to_file("res://scenes/levels/level_custom.tscn")

# ---------- accessors for tests / later phases ----------

func marker_count() -> int:
	return _markers.size()

func validate_count() -> int:
	return validate().size()

func selection_count() -> int:
	return _selection.size()
