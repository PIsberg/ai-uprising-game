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
	var d := LevelDefs.get_def("gpt")
	d["world_scale"] = 1.0
	set_def(d)
	await get_tree().process_frame
	print("SELFTEST markers=", marker_count())
	if _name_edit:
		_name_edit.text = "_selftest"
	_on_save()
	var saved := CustomLevels.load_def("res://dev_levels/_selftest.lvl")
	var ok := marker_count() > 0 and (saved.get("enemies", []) as Array).size() > 0
	print("PHASE1 ", "PASS" if ok else "FAIL")
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
		if event.keycode == KEY_TAB:
			_toggle_view()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _topdown:
				_cam_height = maxf(8.0, _cam_height - 3.0); _apply_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _topdown:
				_cam_height = minf(120.0, _cam_height + 3.0); _apply_camera()
	elif event is InputEventMouseMotion:
		# RMB drag rotates (fly look / top-down yaw).
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			if _topdown:
				_cam_yaw += event.relative.x * 0.01
			else:
				_fly_yaw -= event.relative.x * 0.005
				_fly_pitch = clampf(_fly_pitch - event.relative.y * 0.005, -1.5, 1.5)
			_apply_camera()

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
	var sep := VSeparator.new(); hb.add_child(sep)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	hb.add_child(_status)

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

# ---------- accessors for tests / later phases ----------

func marker_count() -> int:
	return _markers.size()
