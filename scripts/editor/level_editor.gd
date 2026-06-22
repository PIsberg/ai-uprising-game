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
var _models_btn: Button
var _insp_vb: VBoxContainer   # inspector body (rebuilt on selection / def change)
var _use_models := true       # render real game models in the preview (off = fast markers)
var _show_labels := true      # show the floating name labels over markers
var _labels_btn: Button
var _nav_globe: Control       # top-right navigation gizmo (drag-orbit / zoom / pan)
var _nav_sub: SubViewport     # offscreen 3D render of the globe
var _nav_rig: Node3D          # the globe sphere+axes; tumbles to match the view

# ---------- placement / selection / transform (Phase 2) ----------
var _armed_category := ""         # palette item armed for placement ("" = select mode)
var _armed_item := ""
var _selection: Array = []        # selected marker records (subset of _markers)
var _gizmo: Node3D                 # transform gizmo at the selection centroid
var _gizmo_scale := 1.0            # gizmo drawn at this scale (tracks camera distance)
var _handles: Array = []           # [{gtype, axis, dir, off}] draggable gizmo handles
var _hdrag: Dictionary = {}        # active handle drag ({} = none)
var _hdrag_center := Vector3.ZERO
var _hdrag_idx := 0                # axis index 0/1/2 for x/y/z
var _hdrag_s0 := 0.0              # start param along the axis (move/scale)
var _hdrag_a0 := 0.0             # start ground angle (rotate)

# Modal transform (Blender-style G/R/S): "", "move", "rotate", "scale".
var _mode := ""
var _mode_axis := ""              # "", "x", "y", "z"
var _mode_start := Vector3.ZERO   # cursor ground point at mode start
var _mode_orig := []              # snapshot: original {pos,yaw,size} per selected
var _dragging := false            # LMB free-drag move in progress
var _box_select := false          # LMB rubber-band select on empty ground
var _box_start := Vector2.ZERO    # screen-space anchor of the rubber band
var _box_panel: Panel             # the rubber-band overlay (in the UI layer)

# Unsaved-changes tracking.
var _dirty := false               # true once the def is edited since last save/load
var _save_btn: Button
var _grid_btn: Button

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
	"accent": "accents", "target": "targets", "lore": "lore", "lava": "lava",
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
	"accent": Color(0.6, 0.6, 0.65), "target": Color(1.0, 0.7, 0.3),
	"lore": Color(0.5, 0.9, 1.0), "lava": Color(1.0, 0.35, 0.1),
	"set_piece": Color(1.0, 0.25, 0.2),
}

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if has_node("/root/GameState"):
		GameState.set_state(GameState.State.MENU)
		GameState.from_editor = false
	if has_node("/root/AudioBus"):
		AudioBus.set_music_enabled(false) # no music while editing; restored on exit/playtest
		AudioBus.suppress_world_sfx = true # preview enemies stay silent (also avoids leaked playbacks)
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
	var _args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if "--editor-selftest" in _args:
		_selftest.call_deferred()
	elif "--editor-shot" in _args:
		_shot.call_deferred()
	elif "--editor-loadall" in _args:
		_loadall.call_deferred()

## Headless: load EVERY built-in level into the editor and report marker counts.
## Fails if any level produces no markers (i.e. didn't load).
func _loadall() -> void:
	await get_tree().process_frame
	# Marker counts don't depend on real models, and instancing 20 levels' worth of
	# bosses just to count them spawns stray boot timers — use fast markers here.
	_use_models = false
	var fails: Array = []
	for id in _builtin_ids():
		var d := LevelDefs.get_def(id)
		if d.is_empty():
			fails.append("%s(empty)" % id)
			continue
		d["world_scale"] = 1.0
		set_def(d)
		await get_tree().process_frame
		var n := marker_count()
		print("  %-12s %d markers" % [id, n])
		if n < 2: # every level has at least spawn + exit
			fails.append("%s(%d)" % [id, n])
	print("LOADALL ", "PASS" if fails.is_empty() else "FAIL " + ", ".join(fails))
	await _teardown()
	get_tree().quit()

## Free the preview before a headless quit so instanced game scenes (and their
## audio/timers) don't get reported as leaked when we tear down mid-flight.
func _teardown() -> void:
	for c in _preview_root.get_children():
		c.queue_free()
	_markers.clear()
	if _nav_sub and is_instance_valid(_nav_sub): # stop the offscreen render + free its RIDs
		_nav_sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_nav_sub.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

## Windowed screenshot of the editor with a level loaded (dev verification).
func _shot() -> void:
	await get_tree().process_frame
	var d := LevelDefs.get_def("gpt"); d["world_scale"] = 1.0
	set_def(d)
	_cam_height = 46.0
	_apply_camera()
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/editor_shot.png")
	print("SHOT saved")
	await _teardown()
	get_tree().quit()

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
	# Phase 5: draggable gizmo handles (build + Y-move axis targeting + no-crash).
	set_def(blank_def()); await get_tree().process_frame
	_arm("building", "building"); _place_at(Vector3(0, 0, 0)); await get_tree().process_frame
	var handles_ok := _handles.size() == 7 # 3 move + 3 scale + 1 rotate
	_begin_handle_drag({"gtype": "move", "axis": "y", "dir": Vector3.UP, "off": Vector3.UP * 1.7})
	var y_axis_ok := _hdrag_idx == 1 # Y move targets pos.y (the gizmo can't via plane-drag)
	_update_handle_drag(); _hdrag = {}
	_begin_handle_drag({"gtype": "scale", "axis": "x", "dir": Vector3.RIGHT, "off": Vector3.RIGHT * 2.3})
	_update_handle_drag(); _hdrag = {}
	_begin_handle_drag({"gtype": "rotate", "axis": "y", "dir": Vector3.UP, "off": Vector3(0.9, 0, 0.9)})
	_update_handle_drag(); _hdrag = {}
	var p5 := handles_ok and y_axis_ok and (def["buildings"] as Array).size() == 1
	print("P5 handles=", _handles.size(), " y_axis=", y_axis_ok)
	print("PHASE5 ", "PASS" if p5 else "FAIL")
	# Phase 6: camera zoom (proportional, bounded) + gizmo scales with distance.
	_topdown = true
	_cam_height = 38.0
	_wheel(MOUSE_BUTTON_WHEEL_UP)   # zoom in once
	var zoomed_in := _cam_height < 38.0
	for _i in 40: _wheel(MOUSE_BUTTON_WHEEL_UP)   # spam in — must clamp, not crash
	var clamp_lo := _cam_height >= 5.0
	for _i in 80: _wheel(MOUSE_BUTTON_WHEEL_DOWN)  # spam out — must clamp at the top
	var clamp_hi := _cam_height <= 200.0
	# Gizmo tracks camera distance: closer view → smaller gizmo than a far view.
	_cam_height = 12.0; _apply_camera(); _update_gizmo()
	var near_scale := _gizmo_scale
	_cam_height = 160.0; _apply_camera(); _update_gizmo()
	var giz_ok := _gizmo_scale > near_scale
	var p6 := zoomed_in and clamp_lo and clamp_hi and giz_ok
	print("P6 zoom_in=", zoomed_in, " clamp_lo=", clamp_lo, " clamp_hi=", clamp_hi, " gizmo=", giz_ok)
	print("PHASE6 ", "PASS" if p6 else "FAIL")
	# Phase 7: opening the level inspector must not inject out-of-range env defaults
	# (a blanket 1.0 used to bake fog_density 100x over its 0.05 ceiling).
	var dd := blank_def(); dd["env"] = {}
	set_def(dd); await get_tree().process_frame
	_set_selection([])
	_inspect_level()
	var env7: Dictionary = def["env"]
	var fog_ok := float(env7.get("fog_density", 1.0)) <= 0.05
	print("P7 fog_density=", env7.get("fog_density"), " ok=", fog_ok)
	print("PHASE7 ", "PASS" if fog_ok else "FAIL")
	# Phase 8: weapons + powerups place onto a fresh level. extra_weapons isn't in
	# blank_def, so this used to no-op (append on a missing-key null).
	set_def(blank_def()); await get_tree().process_frame
	_arm("weapon", GameState.ALL_WEAPONS[0]); _place_at(Vector3(4, 0, 0)); await get_tree().process_frame
	var wpn_ok := (def.get("extra_weapons", []) as Array).size() == 1
	_arm("pickup", "health"); _place_at(Vector3(-4, 0, 0)); await get_tree().process_frame
	var pwr_ok := (def.get("pickups", []) as Array).size() == 1
	print("P8 weapon=", wpn_ok, " powerup=", pwr_ok)
	print("PHASE8 ", "PASS" if (wpn_ok and pwr_ok) else "FAIL")
	# Phase 9: focus framing, grid cycle, dirty flag, box-select.
	set_def(blank_def()); await get_tree().process_frame
	var clean0 := not _dirty            # fresh load = clean
	_arm("enemy", "android"); _place_at(Vector3(10, 0, 10)); await get_tree().process_frame
	_arm("enemy", "android"); _place_at(Vector3(14, 0, 10)); await get_tree().process_frame
	var dirty_after_edit := _dirty
	# Focus on the selected (2nd) enemy → pan target lands on it.
	_topdown = true; _cam_target = Vector3.ZERO; _cam_height = 38.0; _apply_camera()
	_focus_selection()
	var focus_ok := absf(_cam_target.x - 14.0) < 1.0 and absf(_cam_target.z - 10.0) < 1.0
	# Grid cycle changes the snap step.
	var g0 := _grid; _cycle_grid()
	var grid_ok := _grid != g0
	# Box-select: frame both enemies, build a rect over their projections.
	_cam_target = Vector3(12, 0, 10); _cam_height = 40.0; _apply_camera()
	await get_tree().process_frame
	var pts: Array = []
	for m in _markers:
		if m["category"] == "enemy":
			pts.append(_camera.unproject_position(m["node"].global_position + Vector3(0, 0.8, 0)))
	var box_ok := false
	if pts.size() == 2:
		var mn := Vector2(minf(pts[0].x, pts[1].x), minf(pts[0].y, pts[1].y)) - Vector2(24, 24)
		var mx := Vector2(maxf(pts[0].x, pts[1].x), maxf(pts[0].y, pts[1].y)) + Vector2(24, 24)
		box_ok = _markers_in_rect(Rect2(mn, mx - mn)).size() >= 2
	# Saving clears the dirty flag.
	if _name_edit: _name_edit.text = "_selftest"
	_on_save()
	var clean_after_save := not _dirty
	var p9 := clean0 and dirty_after_edit and focus_ok and grid_ok and box_ok and clean_after_save
	print("P9 clean0=", clean0, " dirty=", dirty_after_edit, " focus=", focus_ok, " grid=", grid_ok, " box=", box_ok, " saved_clean=", clean_after_save)
	print("PHASE9 ", "PASS" if p9 else "FAIL")
	# Phase 10: label visibility toggle.
	set_def(blank_def()); await get_tree().process_frame
	_arm("prop", LevelBuilder.PROP_SCENES.keys()[0]); _place_at(Vector3(0, 0, 0)); await get_tree().process_frame
	var count_labels := func() -> int:
		var n := 0
		for m in _markers:
			for c in m["node"].get_children():
				if c is Label3D and c.visible: n += 1
		return n
	var vis0: int = count_labels.call()
	_toggle_labels()
	var hidden_ok: bool = int(count_labels.call()) == 0 and not _show_labels
	_toggle_labels()
	var shown_ok: bool = int(count_labels.call()) == vis0 and _show_labels and vis0 > 0
	print("P10 vis0=", vis0, " hidden=", hidden_ok, " shown=", shown_ok)
	print("PHASE10 ", "PASS" if (hidden_ok and shown_ok) else "FAIL")
	# Phase 11: nav gizmo built; its pan + zoom helpers drive the camera.
	var nav_ok := _nav_globe != null and is_instance_valid(_nav_globe) and _nav_rig != null
	_topdown = true; _cam_target = Vector3.ZERO; _cam_height = 40.0; _apply_camera()
	_pan_view(Vector2(60, 0))
	var pan_ok := _cam_target.length() > 0.01
	var h0 := _cam_height; _zoom_step(true)
	var zoom_ok := _cam_height < h0
	print("P11 nav=", nav_ok, " pan=", pan_ok, " zoom=", zoom_ok)
	print("PHASE11 ", "PASS" if (nav_ok and pan_ok and zoom_ok) else "FAIL")
	await _teardown()
	get_tree().quit()

## Test helper: drive the scroll-wheel zoom path without a live input device.
func _wheel(button: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	_handle_mouse_button(ev)

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
	# Guarantee every array a category can append to exists, so placement/paste
	# can append without per-call null checks. Sourced from CAT_ARRAY so adding a
	# new placeable category can't silently miss its backing array (weapons used to
	# fail this way: extra_weapons wasn't seeded, so placing one did nothing).
	for k in CAT_ARRAY.values():
		if not (def.get(k) is Array):
			def[k] = []
	if not (def.get("tasks") is Array):
		def["tasks"] = []
	if not (def.get("env") is Dictionary):
		def["env"] = {}
	_cam_target = Vector3(0, 0, 0)
	rebuild_preview()
	_refresh_inspector()
	_clean() # a freshly loaded/blanked def has no unsaved edits
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
	for e in def.get("accents", []):
		_add_marker("accent", e, "pos")
	for e in def.get("targets", []):
		_add_marker("target", e, "pos")
	for e in def.get("lore", []):
		_add_marker("lore", e, "pos")
	for e in def.get("lava", []):
		_add_marker("lava", e, "pos")
	if def.get("set_piece") is Dictionary and not (def["set_piece"] as Dictionary).is_empty():
		_add_marker("set_piece", def["set_piece"], "pos")
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
	# Drop the floor a hair below 0 so structure/prop bases (authored at y=0) are
	# never coplanar with it — coplanar faces z-fight and read as "blinking".
	floor_mi.position.y = -0.05
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
	# Any enemy scene we instanced enters the tree (and runs _ready) here — kill
	# its AI/physics now so it stands still as a pure visual.
	_freeze_preview(node)
	node.set_meta("category", category)
	node.set_meta("holder", holder)
	node.set_meta("key", key)
	_markers.append({"node": node, "category": category, "holder": holder, "key": key})

## Neutralise any physics body in a freshly-added preview node so it can't run
## AI, pathfind, fall, or shoot — it just poses for the editor.
func _freeze_preview(n: Node) -> void:
	for c in n.get_children():
		if c is CharacterBody3D:
			(c as CharacterBody3D).velocity = Vector3.ZERO
			c.set_physics_process(false)
			c.set_process(false)
		elif c is RigidBody3D:
			(c as RigidBody3D).freeze = true
			c.set_physics_process(false)
		# Game scenes auto-play idle/spawn SFX in _ready — silence them (no audio
		# blaring while editing) and drop the stream ref so it can't leak at exit.
		if c is AudioStreamPlayer or c is AudioStreamPlayer3D or c is AudioStreamPlayer2D:
			if c.playing: c.stop()
			c.autoplay = false
			c.stream = null
		_freeze_preview(c)

func _make_marker_visual(category: String, holder: Dictionary) -> Node3D:
	var root := Node3D.new()
	var col: Color = CAT_COLOR.get(category, Color.WHITE)
	# Real game model first (when enabled); fall back to the cheap marker below.
	if _use_models:
		var real: Node3D = _real_visual(category, holder)
		if real != null:
			root.add_child(real)
			_add_label(root, category, holder, col)
			return root
	match category:
		"wall", "building", "ramp", "platform", "accent":
			# Box sized to the entry's `size`.
			var size: Vector3 = holder.get("size", Vector3(2, 3, 2))
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new(); bm.size = size; mi.mesh = bm
			mi.material_override = _flat(col, 0.35)
			root.add_child(mi)
		"lava":
			# Lava `size` is a Vector2 (x,z) footprint — draw a flat slab.
			var sz = holder.get("size", Vector2(8, 3))
			var foot := Vector3(sz.x, 0.2, sz.y) if sz is Vector2 else Vector3(8, 0.2, 3)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new(); bm.size = foot; mi.mesh = bm
			mi.material_override = _emis(col)
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
	_add_label(root, category, holder, col)
	return root

func _add_label(root: Node3D, category: String, holder: Dictionary, col: Color) -> void:
	var lbl := Label3D.new()
	lbl.text = _marker_label(category, holder)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 48
	lbl.pixel_size = 0.01
	lbl.position.y = 2.4
	lbl.modulate = col
	lbl.outline_size = 8
	lbl.visible = _show_labels
	root.add_child(lbl)

## Build the real game visual for an entity, or null to fall back to a marker.
## Enemies/props are instanced from the same scenes LevelBuilder uses; structures
## reuse the builder's beveled mesh + materials; weapons load their real GLB.
func _real_visual(category: String, holder: Dictionary):
	match category:
		"enemy", "boss":
			var scn: PackedScene = LevelBuilder.ENEMY_SCENES.get(String(holder.get("type", "")))
			if scn == null:
				return null
			var bot: Node3D = scn.instantiate()
			if "preview" in bot:
				bot.preview = true   # bosses skip their boot/wave logic in preview
			bot.set_physics_process(false)
			if holder.has("yaw"):
				bot.rotation.y = deg_to_rad(holder["yaw"])
			return bot
		"prop":
			var scn: PackedScene = LevelBuilder.PROP_SCENES.get(String(holder.get("type", "")))
			if scn == null:
				return null
			var p: Node3D = scn.instantiate()
			if holder.has("yaw"):
				p.rotation.y = deg_to_rad(holder["yaw"])
			return p
		"weapon":
			return _weapon_visual(holder)
		"wall", "building", "ramp", "platform", "accent":
			return _structure_visual(category, holder)
	return null

## Beveled box with the builder's real material (matches the in-game look).
func _structure_visual(category: String, holder: Dictionary) -> Node3D:
	var size: Vector3 = holder.get("size", Vector3(2, 3, 2))
	var mi := MeshInstance3D.new()
	var bm := BeveledBoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat: Material
	match category:
		"wall": mat = LevelBuilder.MAT_WALL
		"building": mat = LevelBuilder.MAT_WALL_OUT
		"ramp", "platform": mat = LevelBuilder.MAT_PROP
		_: mat = LevelBuilder.MAT_TRIM
	if holder.has("color"):
		mat = _flat(holder["color"])
	mi.material_override = mat
	# Ramps carry pitch/yaw; orient the slab like the builder does.
	if category == "ramp":
		mi.rotation = Vector3(deg_to_rad(holder.get("pitch", 0.0)), deg_to_rad(holder.get("yaw", 0.0)), 0.0)
	return mi

## Load a weapon's real GLB (Weapon.REAL_MODELS), scaled to its barrel length and
## tinted gunmetal, floating like a pickup.
func _weapon_visual(holder: Dictionary):
	var key := String(holder.get("scene", "")).get_file().get_basename()
	var cfg: Dictionary = Weapon.REAL_MODELS.get(key, {})
	if cfg.is_empty() or not ResourceLoader.exists(cfg["glb"]):
		return null
	var model: Node3D = load(cfg["glb"]).instantiate()
	var aabb := _merged_aabb(model)
	if aabb.size.z > 0.0:
		model.scale = Vector3.ONE * (float(cfg["len"]) / aabb.size.z)
	var holder_node := Node3D.new()
	model.position.y = 1.0   # float at chest height
	model.rotation.y = PI * 0.25
	holder_node.add_child(model)
	return holder_node

## Merged local AABB across a node's MeshInstance3D descendants (for fitting).
func _merged_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = (mi as MeshInstance3D).get_aabb()
		if first:
			out = a; first = false
		else:
			out = out.merge(a)
	return out

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
	# A tight near/far keeps the depth buffer precise — a 2000:0.05 ratio used to
	# z-fight (buildings flickering against the floor at grazing angles).
	_camera.near = 0.2
	_camera.far = 600.0
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
	_update_nav()

## Tumble the 3D nav globe to match the current view orientation (yaw + tilt).
func _update_nav() -> void:
	if _nav_rig == null or not is_instance_valid(_nav_rig):
		return
	var yaw := _cam_yaw if _topdown else _fly_yaw
	var pitch := 1.05 if _topdown else (-_fly_pitch) # top-down looks steeply down
	_nav_rig.rotation = Vector3(pitch, yaw, 0.0)

## Turn the view by a mouse swipe (top-down: orbit yaw; free-fly: look around).
func _orbit(rel: Vector2) -> void:
	if _topdown:
		_cam_yaw += rel.x * 0.01
	else:
		_fly_yaw -= rel.x * 0.005
		_fly_pitch = clampf(_fly_pitch - rel.y * 0.005, -1.5, 1.5)
	_apply_camera()

## Zoom one proportional step: drop/raise the top-down camera, or dolly the
## free-fly camera along its view axis. Shared by the scroll wheel and the nav gizmo.
func _zoom_step(inward: bool) -> void:
	if _topdown:
		_cam_height = clampf(_cam_height * (0.88 if inward else 1.136), 5.0, 200.0)
	else:
		_fly_pos += _camera.global_transform.basis.z * (-4.0 if inward else 4.0)
	_apply_camera()
	_update_nav()

## Pan ("span") the view by a screen-space drag delta — slides the top-down pan
## target, or strafes the free-fly camera. Used by the nav gizmo's pan pad.
func _pan_view(rel: Vector2) -> void:
	if _topdown:
		var d := Basis(Vector3.UP, _cam_yaw) * Vector3(-rel.x, 0.0, -rel.y)
		_cam_target += d * (_cam_height * 0.0022)
	else:
		_fly_pos += _camera.global_transform.basis * Vector3(-rel.x, rel.y, 0.0) * 0.06
	_apply_camera()

## Recenter (and reframe) the view on the selection, or the whole level if nothing
## is selected. Top-down moves the pan target + fits the height; free-fly drops the
## camera back to look at the centroid. Panning is WASD-only, so this is the quick
## way to reach a far corner of a big level.
func _focus_selection() -> void:
	var center := Vector3.ZERO
	var radius := 8.0
	if _selection.is_empty():
		var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
		radius = maxf(fs.x, fs.y) * 0.5
	else:
		for m in _selection:
			center += m["node"].global_position
		center /= _selection.size()
		radius = 6.0
		for m in _selection:
			radius = maxf(radius, m["node"].global_position.distance_to(center) + 4.0)
	if _topdown:
		_cam_target = Vector3(center.x, 0.0, center.z)
		_cam_height = clampf(radius * 2.2, 5.0, 200.0)
	else:
		_fly_pos = center + Vector3(0, radius * 0.8, radius * 1.6)
		_fly_yaw = 0.0
		_fly_pitch = -0.5
	_apply_camera()
	_set_status("Focused")

## Cycle the placement/snap grid through a few useful steps.
func _cycle_grid() -> void:
	var steps := [0.5, 1.0, 2.0, 5.0]
	var i := steps.find(_grid)
	_grid = steps[(i + 1) % steps.size()]
	if _grid_btn: _grid_btn.text = "Grid: %s" % _grid

# ---------- rubber-band (box) select ----------

func _update_box_panel() -> void:
	var cur := get_viewport().get_mouse_position()
	_box_panel.position = Vector2(minf(_box_start.x, cur.x), minf(_box_start.y, cur.y))
	_box_panel.size = (cur - _box_start).abs()

## Select every marker whose screen projection falls inside the rubber band. A
## negligible drag (a plain click) just clears the selection. Shift keeps the
## existing selection and adds to it.
func _finish_box_select() -> void:
	_box_select = false
	_box_panel.visible = false
	var cur := get_viewport().get_mouse_position()
	var rect := Rect2(Vector2(minf(_box_start.x, cur.x), minf(_box_start.y, cur.y)), (cur - _box_start).abs())
	if rect.size.length() < 6.0:
		if not Input.is_key_pressed(KEY_SHIFT):
			_set_selection([])
		return
	var hits := _markers_in_rect(rect)
	if Input.is_key_pressed(KEY_SHIFT):
		for m in _selection:
			if m not in hits:
				hits.append(m)
	_set_selection(hits)
	_set_status("Box-selected %d" % hits.size())

## Markers whose world position projects to a screen point inside `rect`.
func _markers_in_rect(rect: Rect2) -> Array:
	var out: Array = []
	for m in _markers:
		var wp: Vector3 = m["node"].global_position + Vector3(0, 0.8, 0)
		if _camera.is_position_behind(wp):
			continue
		if rect.has_point(_camera.unproject_position(wp)):
			out.append(m)
	return out

# ---------- unsaved-changes guard ----------

## Mark the def edited since the last save/load and reflect it on the Save button.
func _mark_dirty() -> void:
	if _dirty:
		return
	_dirty = true
	if _save_btn: _save_btn.text = "Save *"

func _clean() -> void:
	_dirty = false
	if _save_btn: _save_btn.text = "Save"

## Run `action`, but if there are unsaved edits, confirm first so work isn't lost.
func _guard(action: Callable) -> void:
	if not _dirty:
		action.call()
		return
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Discard unsaved changes?"
	dlg.ok_button_text = "Discard"
	dlg.confirmed.connect(func():
		action.call()
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()

# ---------- input / camera control ----------

func _process(delta: float) -> void:
	if not _hdrag.is_empty():
		_update_handle_drag()
		return
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
			if Input.is_key_pressed(KEY_SHIFT): sp *= 3.0 # hold Shift to sprint
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
			var sp := 60.0 if Input.is_key_pressed(KEY_SHIFT) else 20.0 # Shift = sprint
			_fly_pos += _camera.global_transform.basis * dir.normalized() * sp * delta
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
		# RMB drag turns the camera; LMB drag either resizes the rubber band or
		# moves the selection.
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_orbit(event.relative)
		elif _box_select:
			_update_box_panel()
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
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not _hdrag.is_empty():
				_hdrag = {}
				_set_status("OK")
			if _box_select:
				_finish_box_select()
			_dragging = false
		return
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_zoom_step(true)
		MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_step(false)
		MOUSE_BUTTON_LEFT:
			if _mode != "":
				_confirm_mode() # click confirms an active grab/rotate/scale
				return
			if _armed_category != "":
				_place_at(_cursor_world())
				return
			# Double-click a marker → frame the camera on it.
			if event.double_click and _pick_marker() != null:
				_click_select(false)
				_focus_selection()
				return
			# Grab a gizmo handle if the cursor is over one; a marker to select it;
			# else start a rubber-band box select on empty ground.
			var h = _pick_handle()
			if h != null:
				_begin_handle_drag(h)
			elif _pick_marker() != null or event.shift_pressed:
				_click_select(event.shift_pressed)
			else:
				_box_select = true
				_box_start = get_viewport().get_mouse_position()
				_box_panel.position = _box_start
				_box_panel.size = Vector2.ZERO
				_box_panel.visible = true
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
	_add_btn(hb, "New", func(): _guard(_on_new))
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(160, 0)
	_name_edit.placeholder_text = "level name"
	_name_edit.text = current_name
	hb.add_child(_name_edit)
	_save_btn = _add_btn(hb, "Save", _on_save)
	_load_opt = OptionButton.new()
	_load_opt.custom_minimum_size = Vector2(220, 0)
	hb.add_child(_load_opt)
	_add_btn(hb, "Load", func(): _guard(_on_load))
	_add_btn(hb, "View (Tab)", _toggle_view)
	_add_btn(hb, "⊙ Focus", _focus_selection)
	_snap_btn = _add_btn(hb, "Snap: ON", _toggle_snap)
	_grid_btn = _add_btn(hb, "Grid: 1.0", _cycle_grid)
	_models_btn = _add_btn(hb, "Models: ON", _toggle_models)
	_labels_btn = _add_btn(hb, "Labels: ON", _toggle_labels)
	_add_btn(hb, "Validate", _on_validate)
	var pt := _add_btn(hb, "▶ Playtest", _on_playtest)
	pt.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	var ex := _add_btn(hb, "✕ Exit", func(): _guard(_on_exit))
	ex.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	var sep := VSeparator.new(); hb.add_child(sep)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	hb.add_child(_status)
	_build_palette(layer)
	_build_selection_panel(layer)
	_build_inspector(layer)
	# Rubber-band selection overlay (drawn over the world, hidden until dragging).
	_box_panel = Panel.new()
	_box_panel.visible = false
	_box_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box_panel.modulate = Color(0.5, 0.8, 1.0, 0.5)
	layer.add_child(_box_panel)
	_build_nav_gizmo(layer)

## Blender-style navigation gizmo, top-right of the viewport (just left of the
## inspector): an actual 3D globe (rendered in an offscreen SubViewport) that you
## drag to orbit and scroll to zoom, with pan and zoom buttons below. The globe
## tumbles to reflect the camera orientation. Mouse-only nav, no hotkeys needed.
func _build_nav_gizmo(layer: CanvasLayer) -> void:
	var nav := VBoxContainer.new()
	nav.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	nav.anchor_left = 1.0; nav.anchor_right = 1.0
	nav.offset_left = -416.0; nav.offset_right = -312.0 # sit left of the 300px inspector
	nav.offset_top = 50.0
	nav.add_theme_constant_override("separation", 4)
	layer.add_child(nav)
	# --- offscreen 3D render of the globe ---
	_nav_sub = SubViewport.new()
	_nav_sub.size = Vector2i(112, 112)
	_nav_sub.transparent_bg = true
	_nav_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_nav_sub.msaa_3d = Viewport.MSAA_4X
	add_child(_nav_sub)
	var ge := WorldEnvironment.new()
	var genv := Environment.new()
	genv.background_mode = Environment.BG_CLEAR_COLOR
	genv.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	genv.ambient_light_color = Color(0.5, 0.6, 0.8)
	genv.ambient_light_energy = 1.2
	ge.environment = genv
	_nav_sub.add_child(ge)
	var gcam := Camera3D.new()
	gcam.position = Vector3(0, 0, 3.0)
	gcam.fov = 40.0
	_nav_sub.add_child(gcam)
	var glight := DirectionalLight3D.new()
	glight.rotation_degrees = Vector3(-40, -35, 0)
	glight.light_energy = 1.3
	_nav_sub.add_child(glight)
	_nav_rig = Node3D.new()
	_nav_sub.add_child(_nav_rig)
	_build_globe_mesh(_nav_rig)
	# --- the globe display: a TextureRect fed by the SubViewport, drag/scroll on it ---
	var globe := TextureRect.new()
	globe.texture = _nav_sub.get_texture()
	globe.custom_minimum_size = Vector2(96, 96)
	globe.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	globe.tooltip_text = "Drag: rotate · Scroll: zoom"
	nav.add_child(globe)
	_nav_globe = globe
	globe.gui_input.connect(_on_globe_input)
	# --- zoom / pan row ---
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	nav.add_child(row)
	_nav_btn(row, "−", "Zoom out", func(): _zoom_step(false))
	_nav_pan_pad(row)
	_nav_btn(row, "+", "Zoom in", func(): _zoom_step(true))
	_update_nav()

func _nav_btn(parent: Node, text: String, tip: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(30, 26)
	b.pressed.connect(cb)
	parent.add_child(b)

## A small "✥" pad in the nav gizmo: drag it to pan ("span") the board.
func _nav_pan_pad(parent: Node) -> void:
	var pad := Button.new()
	pad.text = "✥"
	pad.tooltip_text = "Drag to pan the board"
	pad.custom_minimum_size = Vector2(30, 26)
	pad.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_pan_view(e.relative))
	parent.add_child(pad)

func _on_globe_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_orbit(e.relative)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_step(true)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_step(false)

## Build the globe: a core sphere, glowing equator + meridian rings, and coloured
## axis nubs (+X red, +Y green, +Z blue) so the view orientation is readable.
func _build_globe_mesh(rig: Node3D) -> void:
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.9; sm.height = 1.8; sm.radial_segments = 32; sm.rings = 16
	core.mesh = sm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.15, 0.34, 0.6)
	cmat.metallic = 0.2; cmat.roughness = 0.5
	cmat.emission_enabled = true; cmat.emission = Color(0.1, 0.22, 0.42); cmat.emission_energy_multiplier = 0.4
	core.material_override = cmat
	rig.add_child(core)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.5, 0.8, 1.0)
	ring_mat.emission_enabled = true; ring_mat.emission = Color(0.45, 0.75, 1.0); ring_mat.emission_energy_multiplier = 1.3
	for rot in [Vector3.ZERO, Vector3(0, 0, PI * 0.5), Vector3(PI * 0.5, 0, 0)]:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new(); tm.inner_radius = 0.88; tm.outer_radius = 0.95; tm.rings = 40; tm.ring_segments = 8
		ring.mesh = tm
		ring.material_override = ring_mat
		ring.rotation = rot
		rig.add_child(ring)
	var axes := {Vector3.RIGHT: Color(1, 0.32, 0.3), Vector3.UP: Color(0.4, 1, 0.45), Vector3.BACK: Color(0.45, 0.62, 1)}
	for dir in axes:
		var nub := MeshInstance3D.new()
		var ns := SphereMesh.new(); ns.radius = 0.15; ns.height = 0.3
		nub.mesh = ns
		var nm := StandardMaterial3D.new()
		nm.albedo_color = axes[dir]
		nm.emission_enabled = true; nm.emission = axes[dir]; nm.emission_energy_multiplier = 0.8
		nub.material_override = nm
		nub.position = dir * 0.98
		rig.add_child(nub)

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
	return "LMB place/select · dbl-click: focus · drag empty ground: box-select (Shift adds) · drag gizmo handles: ↑arrows move (incl. Y), cubes scale, ring rotate · or G/R/F keys (X/Y/Z) · Del · Ctrl+D/C/V/Z/Y · Tab view · WASD move (Shift sprint) · RMB: turn · scroll: zoom"

func _toggle_snap() -> void:
	_snap = not _snap
	if _snap_btn: _snap_btn.text = "Snap: %s" % ("ON" if _snap else "OFF")

## Toggle real game models vs. cheap markers (markers are faster on big levels).
func _toggle_models() -> void:
	_use_models = not _use_models
	if _models_btn: _models_btn.text = "Models: %s" % ("ON" if _use_models else "OFF")
	var keep := _selection_holders()
	rebuild_preview()
	_select_holders(keep)

## Show/hide the floating name labels (they clutter dense levels). Toggles the
## existing labels live; new markers honour the flag via _add_label.
func _toggle_labels() -> void:
	_show_labels = not _show_labels
	if _labels_btn: _labels_btn.text = "Labels: %s" % ("ON" if _show_labels else "OFF")
	for m in _markers:
		for c in m["node"].get_children():
			if c is Label3D:
				c.visible = _show_labels

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
	# Every key in LevelDefs._defs() (campaign + sandbox).
	return ["01", "gpt", "gemini", "claude", "grok", "suburb", "suburb_boss",
		"mistral", "overseer", "alien", "uplink", "assembly", "titan", "archon",
		"range", "horde", "sublevel", "crucible", "frostbreak", "neon"]

# ---------- file ops ----------

## Leave the editor: back to the main menu if it exists, else quit the app.
func _on_exit() -> void:
	if has_node("/root/AudioBus"):
		AudioBus.set_music_enabled(true)
		AudioBus.suppress_world_sfx = false
	if has_node("/root/GameState"):
		GameState.from_editor = false
	if ResourceLoader.exists("res://scenes/ui/main_menu.tscn"):
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	else:
		get_tree().quit()

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
	if p != "": _clean()
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
		_mark_dirty()
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
	for k in ["hero", "nexus", "weapon", "set_piece"]:
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
	_mark_dirty()

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
	# Keep the gizmo a roughly constant on-screen size across the zoom range —
	# otherwise it shrinks to an ungrabbable dot when zoomed out and bloats when
	# zoomed in. Handle picking reads the same factor (_gizmo_scale).
	if _camera != null:
		var dist := _camera.global_position.distance_to(_gizmo.global_position)
		_gizmo_scale = clampf(dist * 0.03, 0.5, 8.0)
		_gizmo.scale = Vector3.ONE * _gizmo_scale
	_gizmo.visible = true

# --- draggable gizmo handles ---

func _snapshot_sel() -> void:
	_mode_orig.clear()
	for m in _selection:
		var h: Dictionary = m["holder"]
		_mode_orig.append({"pos": h.get(m["key"], Vector3.ZERO), "yaw": h.get("yaw", 0.0), "size": h.get("size", Vector3.ONE)})

## Nearest gizmo handle under the cursor (or null). Only when something's selected.
func _pick_handle():
	if _selection.is_empty() or _gizmo == null or not _gizmo.visible:
		return null
	var r := _ray()
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	var best = null
	var best_dist := 1e9
	for h in _handles:
		# Offsets are authored at unit scale; the gizmo is drawn at _gizmo_scale,
		# so pick against the scaled offset (and widen the grab radius to match).
		var p: Vector3 = _gizmo.global_position + (h["off"] as Vector3) * _gizmo_scale
		var t: float = (p - o).dot(d)
		if t < 0.0:
			continue
		var dist: float = (o + d * t).distance_to(p)
		if dist < maxf(0.4, t * 0.05) * _gizmo_scale and dist < best_dist:
			best_dist = dist
			best = h
	return best

func _begin_handle_drag(h: Dictionary) -> void:
	_push_undo()
	_snapshot_sel()
	_hdrag = h
	_hdrag_center = _gizmo.global_position
	_hdrag_idx = "xyz".find(h["axis"])
	if h["gtype"] == "rotate":
		_hdrag_a0 = _ground_angle(_hdrag_center)
	else:
		_hdrag_s0 = _axis_param(_hdrag_center, h["dir"])
	_set_status("%s %s" % [String(h["gtype"]).to_upper(), String(h["axis"]).to_upper()])

func _update_handle_drag() -> void:
	var dir: Vector3 = _hdrag["dir"]
	match _hdrag["gtype"]:
		"move":
			var moved := _axis_param(_hdrag_center, dir) - _hdrag_s0
			if _snap:
				moved = round(moved / _grid) * _grid
			for i in _selection.size():
				var m: Dictionary = _selection[i]
				var np: Vector3 = _mode_orig[i]["pos"]
				np[_hdrag_idx] += moved
				(m["holder"] as Dictionary)[m["key"]] = np
				m["node"].global_position = np
		"scale":
			var delta := _axis_param(_hdrag_center, dir) - _hdrag_s0
			if _snap:
				delta = round(delta * 2.0) / 2.0
			for i in _selection.size():
				var m: Dictionary = _selection[i]
				if not (m["holder"] as Dictionary).has("size"):
					continue
				var sz: Vector3 = _mode_orig[i]["size"]
				sz[_hdrag_idx] = maxf(0.3, sz[_hdrag_idx] + delta)
				(m["holder"] as Dictionary)["size"] = sz
			_live() # rebuild box markers at the new size
		"rotate":
			var yaw := _snap_deg((_mode_orig[0]["yaw"] as float) + rad_to_deg(_ground_angle(_hdrag_center) - _hdrag_a0))
			for m in _selection:
				(m["holder"] as Dictionary)["yaw"] = yaw
				m["node"].rotation.y = deg_to_rad(yaw)
	_update_gizmo()

## Parameter s along the line (center + dir*s) nearest the mouse ray.
func _axis_param(center: Vector3, dir: Vector3) -> float:
	var r := _ray()
	var o: Vector3 = r[0]
	var u: Vector3 = r[1]
	var w0 := o - center
	var b := u.dot(dir)
	var denom := 1.0 - b * b
	if absf(denom) < 1e-4:
		return dir.dot(w0)
	return (dir.dot(w0) - b * u.dot(w0)) / denom

func _ground_angle(center: Vector3) -> float:
	var c := _cursor_world()
	return atan2(c.x - center.x, c.z - center.z)

## Build the transform gizmo with DRAGGABLE handles: 3 move arrows (x/y/z),
## 3 scale cubes (x/y/z, beyond the arrows), and a yaw rotate handle. Each is
## registered in _handles with its grab type, axis, world direction and the local
## offset used to ray-pick it.
func _make_gizmo() -> Node3D:
	var root := Node3D.new()
	_handles.clear()
	var dirs := {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}
	var cols := {"x": Color(1, 0.3, 0.3), "y": Color(0.3, 1, 0.3), "z": Color(0.45, 0.55, 1)}
	for ax in dirs:
		var dir: Vector3 = dirs[ax]
		var col: Color = cols[ax]
		# Move arrow (shaft).
		var shaft := MeshInstance3D.new()
		var cyl := CylinderMesh.new(); cyl.top_radius = 0.045; cyl.bottom_radius = 0.045; cyl.height = 1.6
		shaft.mesh = cyl
		shaft.material_override = _emis_unshaded(col)
		shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_orient_along(shaft, dir, dir * 0.8)
		root.add_child(shaft)
		# Arrow tip (pickable point for move).
		var tip := MeshInstance3D.new()
		var cone := CylinderMesh.new(); cone.top_radius = 0.0; cone.bottom_radius = 0.16; cone.height = 0.34
		tip.mesh = cone
		tip.material_override = _emis_unshaded(col)
		tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_orient_along(tip, dir, dir * 1.7)
		root.add_child(tip)
		_handles.append({"gtype": "move", "axis": ax, "dir": dir, "off": dir * 1.7})
		# Scale cube (further out).
		var cube := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(0.26, 0.26, 0.26)
		cube.mesh = bm
		cube.material_override = _emis_unshaded(col.darkened(0.25))
		cube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cube.position = dir * 2.3
		root.add_child(cube)
		_handles.append({"gtype": "scale", "axis": ax, "dir": dir, "off": dir * 2.3})
	# Yaw rotate handle (a ring + a pickable knob on the X/Z diagonal).
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = 1.25; tm.outer_radius = 1.35; tm.rings = 32; tm.ring_segments = 8
	ring.mesh = tm
	ring.material_override = _emis_unshaded(Color(1, 0.85, 0.3))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var knob := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.18; sm.height = 0.36
	knob.mesh = sm
	knob.material_override = _emis_unshaded(Color(1, 0.85, 0.3))
	knob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var diag := (Vector3.RIGHT + Vector3.BACK).normalized() * 1.3
	knob.position = diag
	root.add_child(knob)
	_handles.append({"gtype": "rotate", "axis": "y", "dir": Vector3.UP, "off": diag})
	return root

func _emis_unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.4
	return m

## Orient a +Y mesh (cylinder/cone) to point along `dir`, centred at `pos`.
func _orient_along(mi: MeshInstance3D, dir: Vector3, pos: Vector3) -> void:
	if dir.is_equal_approx(Vector3.UP):
		mi.position = pos
	elif dir.is_equal_approx(Vector3.RIGHT):
		mi.rotation_degrees = Vector3(0, 0, -90); mi.position = pos
	else: # BACK
		mi.rotation_degrees = Vector3(90, 0, 0); mi.position = pos

# ---------- inspector / level settings / tasks (Phase 3) ----------

var _editing := false # suppress inspector rebuild while typing in a field

const ENV_COLORS := ["sky_top", "sky_horizon", "ground", "fog", "ambient", "sun_color", "building_tint"]
## key -> [min, max, step, default]. The default matters: it's what gets written
## when a level lacks the key and the inspector materialises the field. A blanket
## 1.0 used to fog levels solid (fog_density's max is 0.05) — hence per-key values.
const ENV_NUMS := {
	"fog_density": [0.0, 0.05, 0.001, 0.01], "ambient_energy": [0.0, 6.0, 0.1, 1.5],
	"sun_energy": [0.0, 6.0, 0.1, 1.4], "glow": [0.0, 2.0, 0.05, 0.5],
	"brightness": [0.5, 1.5, 0.02, 1.0], "contrast": [0.5, 1.8, 0.02, 1.0],
	"saturation": [0.0, 2.0, 0.02, 1.0], "sky_energy": [0.0, 4.0, 0.1, 1.0],
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
	le.text_changed.connect(func(t): holder[key] = t; _mark_dirty())
	hb.add_child(le)

func _f_num(holder: Dictionary, key: String, label: String, mn: float, mx: float, step: float, do_live := false) -> void:
	var hb := _row(label)
	var sb := SpinBox.new()
	sb.min_value = mn; sb.max_value = mx; sb.step = step
	sb.value = float(holder.get(key, 0.0))
	sb.custom_minimum_size = Vector2(120, 0)
	sb.value_changed.connect(func(v):
		holder[key] = v
		_mark_dirty()
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
			_mark_dirty()
			_live())
		hb.add_child(sb)

func _f_color(holder: Dictionary, key: String, label: String) -> void:
	var hb := _row(label)
	var cp := ColorPickerButton.new()
	cp.color = holder.get(key, Color.WHITE)
	cp.custom_minimum_size = Vector2(120, 24)
	cp.color_changed.connect(func(c): holder[key] = c; _mark_dirty())
	hb.add_child(cp)

func _f_bool(holder: Dictionary, key: String, label: String) -> void:
	var hb := _row(label)
	var cb := CheckBox.new()
	cb.button_pressed = bool(holder.get(key, false))
	cb.toggled.connect(func(p): holder[key] = p; _mark_dirty(); _live())
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
		_mark_dirty()
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
		var spec: Array = ENV_NUMS[k]
		if not env.has(k): env[k] = spec[3]
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
	if has_node("/root/AudioBus"):
		AudioBus.set_music_enabled(true) # restore music for the playtest session
		AudioBus.suppress_world_sfx = false
	if has_node("/root/GameState"):
		GameState.custom_level_path = p
		GameState.from_editor = true
		GameState.set_state(GameState.State.PLAYING)
	get_tree().change_scene_to_file("res://scenes/levels/level_custom.tscn")

# ---------- accessors for tests / later phases ----------

func marker_count() -> int:
	return _markers.size()

func validate_count() -> int:
	return validate().size()

func selection_count() -> int:
	return _selection.size()
