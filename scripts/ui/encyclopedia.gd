extends Node3D
## The bestiary. Inherits the old briefing's "showcase a live enemy" idea but as a
## browsable, one-at-a-time reference: a slowly turning 3D model of the selected
## hostile (the very scene the player fights, idle-animating and periodically
## striking) on a lit stage, with a dossier panel — dossier, strengths,
## weaknesses, and the weapons that counter it. Only hostiles the player has
## actually encountered (GameState.discovered_enemies) are listed.

var _turntable: Node3D
var _bot: Node3D
var _camera: Camera3D
var _strike_accum: float = 0.0

var _types: Array = []   # discovered codex types, in roster order
var _index: int = 0
var _reframe: int = 0    # frames left to re-fit the camera after a model settles

# UI
var _name_lbl: Label
var _count_lbl: Label
var _desc_lbl: Label
var _strengths_lbl: RichTextLabel
var _weaknesses_lbl: RichTextLabel
var _weapons_lbl: RichTextLabel
var _empty_lbl: Label
var _prev_btn: Button
var _next_btn: Button

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.set_state(GameState.State.MENU)
	_build_environment()
	_build_lights()
	_build_stage()
	_build_ui()
	_collect_types()
	_refresh()

func _collect_types() -> void:
	_types.clear()
	for t in EnemyCodex.ORDER:
		if GameState.is_enemy_discovered(t) and EnemyCodex.has(t):
			_types.append(t)

# ---------- 3D stage ----------

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.4, 0.55)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.2
	env.glow_hdr_threshold = 0.95
	we.environment = env
	add_child(we)

func _build_lights() -> void:
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 40.0
	add_child(_camera)
	var key := SpotLight3D.new()
	key.position = Vector3(2.6, 5.0, 4.5)
	add_child(key)
	key.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	key.light_color = Color(1.0, 0.96, 0.92)
	key.light_energy = 5.0 # toned down — 9.0 blew out emissive units (raptor)
	key.spot_range = 24.0
	key.spot_angle = 48.0
	key.shadow_enabled = true
	var fill := OmniLight3D.new()
	fill.position = Vector3(-3.5, 3.0, 3.0)
	fill.light_color = Color(0.45, 0.55, 0.8)
	fill.light_energy = 2.0
	fill.omni_range = 16.0
	add_child(fill)
	# Cool, gentle back-rim. (A hot red rim here reflected off the dais as a
	# distracting "orange ring" on the floor — keep it dim and cool.)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0, 2.6, -3.5)
	rim.light_color = Color(0.5, 0.62, 0.9)
	rim.light_energy = 1.6
	rim.omni_range = 12.0
	add_child(rim)

## A dark reflective dais the model turns on, with a glowing accent ring.
func _build_stage() -> void:
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.4; cm.bottom_radius = 2.6; cm.height = 0.12
	cm.radial_segments = 48
	disc.mesh = cm
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.07, 0.08, 0.1)
	# Matte, not mirror — a glossy metallic disc threw a harsh specular ring.
	dmat.metallic = 0.2; dmat.roughness = 0.85
	disc.material_override = dmat
	disc.position = Vector3(0, -0.06, 0)
	add_child(disc)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.35; tm.outer_radius = 2.5
	tm.rings = 48; tm.ring_segments = 8
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.emission_enabled = true
	rmat.albedo_color = Color(0.3, 0.7, 1.0)
	rmat.emission = Color(0.25, 0.6, 1.0)
	rmat.emission_energy_multiplier = 2.5
	ring.material_override = rmat
	ring.position = Vector3(0, 0.02, 0)
	add_child(ring)
	_turntable = Node3D.new()
	add_child(_turntable)

# ---------- UI ----------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	# Dossier panel down the right side.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.anchor_left = 1.0; panel.anchor_right = 1.0
	panel.offset_left = -640.0; panel.offset_right = -32.0
	panel.offset_top = 40.0; panel.offset_bottom = -110.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.82)
	sb.border_color = Color(0.3, 0.55, 0.9, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	var header := Label.new()
	header.text = "ENEMY CODEX"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	vb.add_child(header)

	_name_lbl = Label.new()
	_name_lbl.add_theme_font_size_override("font_size", 40)
	_name_lbl.add_theme_color_override("font_color", Color(1, 0.95, 0.9))
	vb.add_child(_name_lbl)

	_count_lbl = Label.new()
	_count_lbl.add_theme_font_size_override("font_size", 15)
	_count_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	vb.add_child(_count_lbl)

	_desc_lbl = Label.new()
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_lbl.custom_minimum_size = Vector2(580, 0)
	_desc_lbl.add_theme_font_size_override("font_size", 18)
	_desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	vb.add_child(_desc_lbl)

	vb.add_child(_section_title("STRENGTHS", Color(1.0, 0.55, 0.4)))
	_strengths_lbl = _bullet_list()
	vb.add_child(_strengths_lbl)

	vb.add_child(_section_title("WEAKNESSES", Color(0.5, 0.9, 0.6)))
	_weaknesses_lbl = _bullet_list()
	vb.add_child(_weaknesses_lbl)

	vb.add_child(_section_title("EFFECTIVE WEAPONS", Color(0.5, 0.8, 1.0)))
	_weapons_lbl = _bullet_list()
	vb.add_child(_weapons_lbl)

	# Empty-state message (no hostiles met yet), centered over the screen.
	_empty_lbl = Label.new()
	_empty_lbl.text = "NO HOSTILES ENCOUNTERED YET\n\nFight through the campaign to fill the codex."
	_empty_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_lbl.add_theme_font_size_override("font_size", 26)
	_empty_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	_empty_lbl.visible = false
	layer.add_child(_empty_lbl)

	# Nav bar along the bottom.
	var nav := HBoxContainer.new()
	nav.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	nav.anchor_top = 1.0; nav.anchor_bottom = 1.0
	nav.offset_top = -86.0; nav.offset_bottom = -30.0
	nav.offset_left = 40.0; nav.offset_right = -40.0
	nav.add_theme_constant_override("separation", 16)
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	layer.add_child(nav)

	_prev_btn = Button.new()
	_prev_btn.text = "◂  Prev"
	_prev_btn.custom_minimum_size = Vector2(160, 48)
	_prev_btn.pressed.connect(_on_prev)
	nav.add_child(_prev_btn)

	var back := Button.new()
	back.text = "Back to Menu"
	back.custom_minimum_size = Vector2(220, 48)
	back.pressed.connect(_on_back)
	nav.add_child(back)

	_next_btn = Button.new()
	_next_btn.text = "Next  ▸"
	_next_btn.custom_minimum_size = Vector2(160, 48)
	_next_btn.pressed.connect(_on_next)
	nav.add_child(_next_btn)

func _section_title(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", col)
	return l

func _bullet_list() -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.custom_minimum_size = Vector2(580, 0)
	rt.add_theme_font_size_override("normal_font_size", 17)
	return rt

func _fill_bullets(rt: RichTextLabel, items: Array, col: String) -> void:
	var lines: Array = []
	for it in items:
		lines.append("[color=%s]›[/color]  %s" % [col, str(it)])
	rt.text = "\n".join(lines)

# ---------- selection ----------

func _refresh() -> void:
	var any := _types.size() > 0
	_empty_lbl.visible = not any
	_prev_btn.disabled = _types.size() <= 1
	_next_btn.disabled = _types.size() <= 1
	if not any:
		_name_lbl.text = ""
		_count_lbl.text = ""
		_desc_lbl.text = ""
		_strengths_lbl.text = ""
		_weaknesses_lbl.text = ""
		_weapons_lbl.text = ""
		return
	_index = wrapi(_index, 0, _types.size())
	var t: String = _types[_index]
	var e := EnemyCodex.get_entry(t)
	_name_lbl.text = e.get("name", t.to_upper())
	_count_lbl.text = "%d / %d  encountered" % [_index + 1, _types.size()]
	_desc_lbl.text = e.get("desc", "")
	_fill_bullets(_strengths_lbl, e.get("strengths", []), "#ff8a66")
	_fill_bullets(_weaknesses_lbl, e.get("weaknesses", []), "#7fe69a")
	_fill_bullets(_weapons_lbl, e.get("weapons", []), "#80ccff")
	_spawn_model(e)

## Swap in the selected hostile as a live, idle-animating model on the turntable.
func _spawn_model(entry: Dictionary) -> void:
	if _bot and is_instance_valid(_bot):
		_bot.queue_free()
		_bot = null
	_turntable.rotation = Vector3.ZERO
	var path: String = entry.get("scene", "")
	if path == "":
		return
	var ps: PackedScene = load(path)
	if ps == null:
		return
	var bot: Node3D = ps.instantiate()
	if "preview" in bot:
		bot.preview = true # bosses: show idle only, skip their boot/wave logic
	_turntable.add_child(bot)
	bot.rotation.y = PI # face the camera (+Z)
	bot.scale = Vector3.ONE * float(entry.get("scale", 1.0))
	bot.position = Vector3(0, float(entry.get("y", 0.0)), 0)
	if bot.has_method("set_physics_process"):
		bot.set_physics_process(false) # no AI; RobotModel still idles the clip
	_bot = bot
	_frame_model(bot)
	# RobotModel finishes sizing the chassis over the next frame or two, so the
	# AABB measured right now can be wrong (units ended up too big/small in frame).
	# Re-frame for a few frames once it has settled.
	_reframe = 5

## Distance the camera so the whole chassis fits, framed a little left of centre
## so the right-hand dossier panel doesn't cover it.
func _frame_model(bot: Node3D) -> void:
	var ab := _world_aabb(bot)
	var bottom: float = maxf(ab.position.y, 0.0)
	var top: float = ab.position.y + ab.size.y
	var h: float = maxf(top - bottom, 0.8)
	var w: float = maxf(maxf(ab.size.x, ab.size.z), 0.8)
	var cy := (bottom + top) * 0.5
	var vfov := deg_to_rad(_camera.fov)
	var hfov := 2.0 * atan(tan(vfov * 0.5) * 1.78)
	var d_v := (h * 0.5 * 1.65) / tan(vfov * 0.5)
	var d_h := (w * 0.5 * 1.5) / tan(hfov * 0.5)
	var dist := maxf(maxf(d_v, d_h), 3.0)
	# Aim a touch to the +X side of the model: that pushes the model to screen-left,
	# clear of the dossier panel pinned on the right.
	var shift := dist * 0.22
	_camera.global_position = Vector3(0, cy, dist)
	_camera.look_at(Vector3(shift, cy, 0), Vector3.UP)

func _world_aabb(bot: Node3D) -> AABB:
	# Skinned meshes render via their Skeleton3D bones, NOT the MeshInstance3D's
	# own transform. Several re-exported (Blender-forked) models bake a huge
	# scale into the mesh instance that the skin cancels out, so
	# `global_transform * mesh.get_aabb()` reports a bogus 600-unit box and the
	# framer backs the camera off until the bot is a speck. When a skeleton is
	# present, measure the real posed extent from its bone positions instead.
	var skels := bot.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		var skel := skels[0] as Skeleton3D
		if skel.get_bone_count() > 0:
			var b := AABB()
			var bfirst := true
			for i in skel.get_bone_count():
				var p: Vector3 = (skel.global_transform * skel.get_bone_global_pose(i)).origin
				if bfirst:
					b = AABB(p, Vector3.ZERO); bfirst = false
				else:
					b = b.expand(p)
			# Bones mark joints, not the skin surface — pad so heads/limbs/blades
			# aren't cropped, and floor the bottom at the dais.
			b = b.grow(0.4)
			b.position.y = maxf(b.position.y, 0.0)
			return b

	var merged := AABB()
	var first := true
	for mi in bot.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh:
			var a: AABB = m.global_transform * m.mesh.get_aabb()
			merged = a if first else merged.merge(a)
			first = false
	if first:
		return AABB(Vector3(-0.6, 0, -0.6), Vector3(1.2, 2.0, 1.2))
	return merged

func _process(delta: float) -> void:
	if _reframe > 0 and _bot and is_instance_valid(_bot):
		_reframe -= 1
		_frame_model(_bot) # re-fit while the chassis settles to its final size
	if _turntable:
		_turntable.rotation.y += delta * 0.5 # slow spin
	# Periodically fire the unit's own attack clip (RobotModel reads `recoil`).
	if _bot and is_instance_valid(_bot) and "recoil" in _bot:
		_strike_accum += delta
		if _strike_accum >= 3.0:
			_strike_accum = 0.0
			_bot.recoil = 1.0
			get_tree().create_timer(0.12).timeout.connect(func() -> void:
				if is_instance_valid(_bot): _bot.recoil = 0.0)

# ---------- input / nav ----------

func _on_prev() -> void:
	if _types.size() <= 1:
		return
	_index = wrapi(_index - 1, 0, _types.size())
	_strike_accum = 0.0
	_refresh()

func _on_next() -> void:
	if _types.size() <= 1:
		return
	_index = wrapi(_index + 1, 0, _types.size())
	_strike_accum = 0.0
	_refresh()

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back()
	elif event.is_action_pressed("ui_right"):
		_on_next()
	elif event.is_action_pressed("ui_left"):
		_on_prev()
