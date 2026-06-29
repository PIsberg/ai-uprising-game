extends Control
## The arsenal reference: every weapon in the game with its class, a dossier line,
## and full stats (damage, rate, DPS, magazine, reload, range, headshot, pierce,
## splash) plus comparison bars normalised across the whole arsenal. Reached from
## the main menu, alongside the Enemy Codex. Reads each weapon's WeaponData straight
## off its scene (instantiate without entering the tree, so no _ready side effects).

## Short dossier per weapon, keyed by scene-file basename.
const DOSSIER := {
	"pistol": "Reliable M9 sidearm — deep reserve and clean headshots. Your fallback when everything else runs dry.",
	"rifle": "AR-7 Pulse Rifle — the do-everything full-auto: accurate, controllable, effective at every range.",
	"shotgun": "SG-12 Breacher. A wall of pellets that deletes anything point-blank. SLUG alt collapses it into one heavy round.",
	"magnum": ".50 Maelstrom hand cannon — enormous per-shot damage and headshots, slow and unforgiving.",
	"tesla": "VK-7 Tesla Projector. A vicious close-range arc that shreds armour — but almost no reach, so it leaves you wide open to melee. Get in, zap, get out.",
	"arccoil": "CL-3 Arc Coil — a short-range electric burst that chains between bunched-up machines.",
	"sniper": "MK-VII Longshot. One-shot precision at any distance. CHARGE for a boosted round; weak up close.",
	"plasma": "PL-1 Plasma Launcher — lobbed plasma bolts with splash. Area denial that cooks clustered foes.",
	"gauss": "ARC-9 Gauss Lance. A coil-gun spike that punches clean through a rank of machines.",
	"swarm": "SW-7 Swarm Launcher — fires homing micro-missiles that hunt down whatever you mark.",
	"tempest": "TPX-9 Tempest Coil. Chain lightning that leaps from target to target across a pack.",
	"devastator": "GRK-X Devastator. A heavy rocket launcher: big splash, slow reload. Bring it to a horde.",
	"omega": "OMEGA-X Annihilator — the ultimate. Everything, dialled to maximum. Earn it, then end things.",
}

const FIRE_NAMES := ["SEMI", "AUTO", "BURST", "BEAM"]
const DMG_NAMES := ["HITSCAN", "PROJECTILE"]
const ALT_NAMES := ["", " · CHARGE alt", " · VOLLEY alt", " · SLUG alt"]
const ACCENT := Color(0.5, 0.8, 1.0)

var _weapons: Array = []   # [{id, data}]
var _index: int = 0
var _max: Dictionary = {}  # arsenal maxima for the comparison bars

# UI refs
var _list: VBoxContainer
var _name_lbl: Label
var _class_lbl: Label
var _count_lbl: Label
var _desc_lbl: Label
var _stats: VBoxContainer
var _bars: VBoxContainer
var _list_btns: Array[Button] = []
# 3D preview: a spinning gun model rendered in its own SubViewport.
var _subvp: SubViewport
var _turntable: Node3D
var _cam: Camera3D
var _model: Node3D
# Auto-firing preview: the muzzle node lifted with the viewmodel, plus the live
# WeaponData, so the Codex can spawn the gun's real muzzle flash on a timer.
var _muzzle: Node3D
var _cur_data: WeaponData
var _fire_cd: float = 0.8
var _model_base_pos: Vector3 = Vector3.ZERO
var _recoil_kick: float = 0.0
# Down-range shot FX (tracers / projectiles / beam) spawned in the preview world,
# so the Codex shows each gun's REAL shot leaving the barrel — not just a flash.
var _fx_root: Node3D
var _beam: ElectricBeam
var _beam_hold: float = 0.0   ## seconds the beam stays lit after a "fire" tick

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.set_state(GameState.State.MENU)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_weapons()
	_build_ui()
	_refresh()

## Read each weapon's WeaponData off its scene without entering the tree.
func _load_weapons() -> void:
	var dmg := 1.0; var rof := 1.0; var mag := 1.0; var rng := 1.0
	for path in GameState.WEAPON_ORDER:
		var ps := load(path) as PackedScene
		if ps == null:
			continue
		var inst := ps.instantiate()
		var d := inst.get("data") as WeaponData
		if d != null:
			_weapons.append({"id": String(path).get_file().get_basename(), "data": d, "path": String(path)})
			dmg = maxf(dmg, d.damage * maxi(d.pellets, 1))
			rof = maxf(rof, d.fire_rate)
			mag = maxf(mag, float(d.mag_size))
			rng = maxf(rng, d.range_m)
		inst.free()
	_max = {"dmg": dmg, "rof": rof, "mag": mag, "rng": rng}

# ---------- UI ----------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.04, 0.06)
	add_child(bg)

	var title := Label.new()
	title.text = "WEAPON CODEX"
	title.position = Vector2(48, 34)
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0))
	add_child(title)

	var sub := Label.new()
	sub.text = "The full arsenal. ◂ ▸ to browse · Esc to go back."
	sub.position = Vector2(50, 78)
	sub.add_theme_color_override("font_color", Color(0.55, 0.7, 0.8))
	add_child(sub)

	# Left: scrollable weapon list.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	scroll.offset_left = 48; scroll.offset_right = 360
	scroll.offset_top = 120; scroll.offset_bottom = -96
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	for i in _weapons.size():
		var d: WeaponData = _weapons[i]["data"]
		var b := Button.new()
		b.custom_minimum_size = Vector2(300, 40)
		b.text = "%d.  %s" % [i + 1, d.display_name]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", d.tracer_color.lerp(Color.WHITE, 0.35))
		b.pressed.connect(_select.bind(i))
		_list.add_child(b)
		_list_btns.append(b)

	# Right: dossier panel.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 392; panel.offset_right = -48
	panel.offset_top = 120; panel.offset_bottom = -96
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.1, 0.85)
	sb.border_color = Color(0.3, 0.55, 0.9, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	_build_preview(vb)

	_name_lbl = Label.new()
	_name_lbl.add_theme_font_size_override("font_size", 38)
	_name_lbl.add_theme_color_override("font_color", Color(1, 0.96, 0.9))
	vb.add_child(_name_lbl)

	_class_lbl = Label.new()
	_class_lbl.add_theme_font_size_override("font_size", 16)
	_class_lbl.add_theme_color_override("font_color", ACCENT)
	vb.add_child(_class_lbl)

	_count_lbl = Label.new()
	_count_lbl.add_theme_font_size_override("font_size", 13)
	_count_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	vb.add_child(_count_lbl)

	_desc_lbl = Label.new()
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_lbl.custom_minimum_size = Vector2(640, 0)
	_desc_lbl.add_theme_font_size_override("font_size", 18)
	_desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	vb.add_child(_desc_lbl)

	vb.add_child(_title_label("SPECIFICATIONS"))
	_stats = VBoxContainer.new()
	_stats.add_theme_constant_override("separation", 3)
	vb.add_child(_stats)

	vb.add_child(_title_label("PROFILE"))
	_bars = VBoxContainer.new()
	_bars.add_theme_constant_override("separation", 6)
	vb.add_child(_bars)

	# Bottom nav.
	var nav := HBoxContainer.new()
	nav.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	nav.anchor_top = 1.0; nav.anchor_bottom = 1.0
	nav.offset_top = -78; nav.offset_bottom = -28
	nav.offset_left = 48; nav.offset_right = -48
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 16)
	add_child(nav)
	var prev := Button.new()
	prev.text = "◂  Prev"; prev.custom_minimum_size = Vector2(150, 46)
	prev.pressed.connect(func(): _step(-1))
	nav.add_child(prev)
	var back := Button.new()
	back.text = "Back to Menu"; back.custom_minimum_size = Vector2(220, 46)
	back.pressed.connect(_on_back)
	nav.add_child(back)
	var nxt := Button.new()
	nxt.text = "Next  ▸"; nxt.custom_minimum_size = Vector2(150, 46)
	nxt.pressed.connect(func(): _step(1))
	nav.add_child(nxt)

## A small 3D stage in the dossier that spins the selected weapon's viewmodel.
func _build_preview(vb: VBoxContainer) -> void:
	_subvp = SubViewport.new()
	_subvp.own_world_3d = true
	_subvp.transparent_bg = false
	_subvp.msaa_3d = Viewport.MSAA_4X
	_turntable = Node3D.new()
	_subvp.add_child(_turntable)
	_cam = Camera3D.new()
	_cam.fov = 35.0
	_cam.position = Vector3(0.3, 0.18, 0.45)
	_subvp.add_child(_cam)
	# Orientation is set per-weapon in _frame_model (look_at needs the cam in-tree).
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -36, 0)
	key.light_energy = 2.8
	_subvp.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-0.5, 0.35, 0.45)
	fill.light_color = Color(0.6, 0.72, 0.95)
	fill.light_energy = 3.0
	fill.omni_range = 3.5
	_subvp.add_child(fill)
	# Warm back-rim so the dark gunmetal silhouette pops off the backdrop.
	var rim := OmniLight3D.new()
	rim.position = Vector3(0.3, 0.25, -0.5)
	rim.light_color = Color(1.0, 0.85, 0.6)
	rim.light_energy = 2.4
	rim.omni_range = 3.0
	_subvp.add_child(rim)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.11, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.62)
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	we.environment = env
	_subvp.add_child(we)
	# A static world node the shot FX live in (NOT the turntable — once a bolt
	# leaves the barrel it flies straight; only the gun keeps spinning).
	_fx_root = Node3D.new()
	_subvp.add_child(_fx_root)
	var box := SubViewportContainer.new()
	box.stretch = true
	box.custom_minimum_size = Vector2(0, 200)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_subvp)
	vb.add_child(box)

## Swap in the selected weapon's viewmodel on the turntable. Instantiated but NOT
## added to the scene tree, so weapon.gd's _ready (which expects a camera/player)
## never fires — we lift out just the script-less "Viewmodel" node and free the rest.
func _show_model(scene_path: String) -> void:
	if _turntable == null:
		return
	if _model and is_instance_valid(_model):
		_model.queue_free()
		_model = null
	_muzzle = null
	_turntable.rotation = Vector3.ZERO
	var ps := load(scene_path) as PackedScene
	if ps == null:
		return
	var w := ps.instantiate()
	var vm := w.get_node_or_null("Viewmodel") as Node3D
	if vm:
		w.remove_child(vm)
		vm.owner = null # detach from the freed weapon scene's ownership
		_model = vm
		_turntable.add_child(vm)
		_frame_model()
		# weapon.gd resolves its muzzle the same way: a direct "Muzzle" child of
		# the viewmodel. Lift it so the preview can fire from the barrel tip.
		_muzzle = vm.get_node_or_null("Muzzle")
	w.free()

func _frame_model() -> void:
	if _model == null:
		return
	var aabb := _model_aabb(_model)
	var ctr := aabb.position + aabb.size * 0.5
	_model.position = -ctr # spin around the model's own centre
	var radius: float = maxf(aabb.size.length() * 0.5, 0.14)
	var dist := radius / tan(deg_to_rad(_cam.fov) * 0.5) * 0.78 # tighter so the gun fills the box
	# Side-on 3/4 view (barrel runs across the frame) — the iconic gun profile; it
	# spins from here so every angle shows.
	_cam.position = Vector3(dist * 0.82, dist * 0.34, dist * 0.42)
	_cam.look_at(Vector3.ZERO, Vector3.UP)
	# Remember the framed rest position so the recoil kick can spring back to it.
	_model_base_pos = _model.position
	_recoil_kick = 0.0

func _model_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a: AABB = (inv * m.global_transform) * m.mesh.get_aabb()
		merged = a if first else merged.merge(a)
		first = false
	if first:
		return AABB(Vector3(-0.15, -0.15, -0.15), Vector3(0.3, 0.3, 0.3))
	return merged

func _process(delta: float) -> void:
	if _turntable:
		_turntable.rotation.y += delta * 0.8
	# Spring the viewmodel back from its recoil kick.
	if _model and is_instance_valid(_model):
		_recoil_kick = move_toward(_recoil_kick, 0.0, delta * 0.35)
		_model.position = _model_base_pos + Vector3(0.0, 0.0, _recoil_kick)
	# Beam weapons fire a sustained electric beam (held, like in-game) that tracks
	# the spinning barrel. Everything else auto-fires its real shot on a cadence.
	if _cur_data and _cur_data.fire_mode == WeaponData.FireMode.BEAM:
		_drive_beam(true)
		return
	_drive_beam(false)
	# Auto-fire the previewed weapon on a calm cadence so its muzzle flash, tint,
	# recoil AND real shot (tracer / projectile) read at a glance — a live check
	# that each gun's FX is wired right.
	_fire_cd -= delta
	if _fire_cd <= 0.0:
		_fire_cd = 1.4
		_fire_preview()

## Fire the current weapon in the preview: a recoil kick (scaled by recoil_pitch)
## plus a burst of muzzle flashes (3 for AUTO/BURST guns, 1 otherwise).
func _fire_preview() -> void:
	if _cur_data == null or not is_instance_valid(_muzzle):
		return
	_recoil_kick = clampf(0.008 + _cur_data.recoil_pitch * 0.004, 0.01, 0.045)
	var shots := 1
	if _cur_data.fire_mode == WeaponData.FireMode.AUTO or _cur_data.fire_mode == WeaponData.FireMode.BURST:
		shots = 3
	_fire_burst(shots)

func _fire_burst(n: int) -> void:
	for i in n:
		if _cur_data == null or not is_instance_valid(_muzzle):
			return
		_spawn_flash()
		_spawn_downrange()
		if i < n - 1:
			await get_tree().create_timer(0.09).timeout

## Fire the gun's REAL down-range shot into the preview world: a hitscan gun's
## tracer bolt, or a projectile gun's actual round (gravity zeroed and freed before
## it can detonate, so it just flies the barrel like in-game). Beam guns are driven
## separately by _drive_beam.
func _spawn_downrange() -> void:
	if _cur_data == null or not is_instance_valid(_muzzle) or _fx_root == null:
		return
	var from: Vector3 = _muzzle.global_position
	var fwd: Vector3 = -_muzzle.global_transform.basis.z.normalized()
	if _cur_data.projectile_scene != null:
		_spawn_preview_projectile(from, fwd)
	elif _cur_data.tracer_scene != null:
		_spawn_preview_tracer(from, from + fwd * 2.6)

func _spawn_preview_tracer(from: Vector3, to: Vector3) -> void:
	var t := _cur_data.tracer_scene.instantiate()
	_fx_root.add_child(t)
	# Bolt mode at a calm speed so the shot visibly travels across the small stage.
	if "bolt" in t:
		t.bolt = true
		t.bolt_speed = 7.0
		t.bolt_length = 0.7
		t.bolt_width = 1.4
	if t.has_method("setup"):
		t.setup(from, to, _cur_data.tracer_color)

func _spawn_preview_projectile(from: Vector3, fwd: Vector3) -> void:
	var p := _cur_data.projectile_scene.instantiate()
	_fx_root.add_child(p)
	p.global_position = from + fwd * 0.1
	# Tame it for the tiny stage: no gravity arc, no homing (nothing to chase),
	# and a slow visual speed so the round lingers in frame.
	if "gravity_scale" in p:
		p.gravity_scale = 0.0
	if "homing_turn_rate" in p:
		p.homing_turn_rate = 0.0
	if p.has_method("launch"):
		p.launch(fwd * 2.4, null, 0.0, 0.0, 0.0) # visual only — zero damage/splash
	# Free it before its lifetime expires so the real (off-stage) detonation never
	# fires — we only want the round flying out of the barrel.
	get_tree().create_timer(0.7).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())

## Sustain (or kill) the beam-weapon's electric beam, drawn live from the muzzle
## down-range so it tracks the spinning barrel.
func _drive_beam(active: bool) -> void:
	if not active or not is_instance_valid(_muzzle) or _fx_root == null:
		if _beam and is_instance_valid(_beam):
			_beam.deactivate()
		return
	if _beam == null or not is_instance_valid(_beam):
		_beam = ElectricBeam.new()
		_fx_root.add_child(_beam)
	_beam.set_color(_cur_data.tracer_color)
	var from: Vector3 = _muzzle.global_position
	var fwd: Vector3 = -_muzzle.global_transform.basis.z.normalized()
	_beam.update_beam(from, from + fwd * 2.4, false)

## Spawn the weapon's own muzzle flash at the barrel tip — same tint + size_mult
## weapon.gd uses — so the Codex shows the real per-weapon blast. Energy/beam guns
## carry no flash scene, so they get a tinted bloom instead.
func _spawn_flash() -> void:
	if _cur_data == null or not is_instance_valid(_muzzle):
		return
	var fs: PackedScene = _cur_data.muzzle_flash_scene
	if fs != null:
		var m := fs.instantiate()
		if "tint_color" in m:
			m.tint_color = _cur_data.tracer_color
			m.size_mult = _cur_data.muzzle_scale
		_muzzle.add_child(m)
	else:
		_spawn_energy_bloom()

func _spawn_energy_bloom() -> void:
	var col := _cur_data.tracer_color
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	var r := 0.05 * maxf(_cur_data.muzzle_scale, 0.6)
	sm.radius = r; sm.height = r * 2.0; sm.radial_segments = 10; sm.rings = 6
	orb.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col.r, col.g, col.b, 0.9)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 9.0
	orb.material_override = mat
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle.add_child(orb)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 5.0
	light.omni_range = 2.5
	orb.add_child(light)
	var tw := orb.create_tween()
	tw.set_parallel(true)
	tw.tween_property(orb, "scale", Vector3.ONE * 2.2, 0.18)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tw.tween_property(light, "light_energy", 0.0, 0.18)
	tw.chain().tween_callback(orb.queue_free)

func _title_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	return l

func _stat_row(key: String, val: String) -> void:
	var row := HBoxContainer.new()
	var k := Label.new()
	k.text = key
	k.custom_minimum_size = Vector2(220, 0)
	k.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78))
	k.add_theme_font_size_override("font_size", 16)
	var v := Label.new()
	v.text = val
	v.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	v.add_theme_font_size_override("font_size", 16)
	row.add_child(k); row.add_child(v)
	_stats.add_child(row)

func _bar_row(key: String, ratio: float, col: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var k := Label.new()
	k.text = key
	k.custom_minimum_size = Vector2(120, 0)
	k.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78))
	k.add_theme_font_size_override("font_size", 15)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(420, 16)
	bar.min_value = 0.0; bar.max_value = 1.0
	bar.value = clampf(ratio, 0.03, 1.0)
	bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.12, 0.16); bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col; fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(k); row.add_child(bar)
	_bars.add_child(row)

# ---------- selection ----------

func _select(i: int) -> void:
	_index = i
	AudioBus.play_synth_ui("broadcast_blip", -16.0, 1.6)
	_refresh()

func _step(d: int) -> void:
	if _weapons.is_empty():
		return
	_index = wrapi(_index + d, 0, _weapons.size())
	AudioBus.play_synth_ui("broadcast_blip", -14.0, 1.5)
	_refresh()

func _refresh() -> void:
	if _weapons.is_empty():
		_name_lbl.text = "NO WEAPONS"
		return
	var d: WeaponData = _weapons[_index]["data"]
	var id: String = _weapons[_index]["id"]
	# Drive the firing preview; fire shortly after a switch so it's responsive.
	_cur_data = d
	_fire_cd = 0.6
	_name_lbl.text = d.display_name
	_class_lbl.text = "%s · %s%s" % [
		FIRE_NAMES[clampi(d.fire_mode, 0, 3)], DMG_NAMES[clampi(d.damage_type, 0, 1)],
		ALT_NAMES[clampi(d.alt_mode, 0, 3)]]
	_count_lbl.text = "%d / %d  ·  weakest → strongest" % [_index + 1, _weapons.size()]
	_desc_lbl.text = DOSSIER.get(id, "")

	for c in _stats.get_children():
		c.queue_free()
	var per_shot := d.damage * maxi(d.pellets, 1)
	_stat_row("Damage", "%.0f%s" % [d.damage, "  × %d pellets" % d.pellets if d.pellets > 1 else ""])
	_stat_row("Rate of fire", "%.1f / s" % d.fire_rate)
	_stat_row("Damage per second", "%.0f" % (per_shot * d.fire_rate))
	_stat_row("Magazine", str(d.mag_size))
	_stat_row("Reserve", str(d.reserve_max))
	_stat_row("Reload", "%.1f s" % d.reload_time)
	if d.range_falloff:
		_stat_row("Effective range", "%.0f m  (best %.0f–%.0f m)" % [d.range_m, d.opt_min, d.opt_max])
	else:
		_stat_row("Range", "%.0f m  (flat)" % d.range_m)
	_stat_row("Headshot", "%.1f ×" % d.headshot_mult)
	if d.pierce > 0:
		_stat_row("Pierce", "+%d targets" % d.pierce)
	if d.damage_type == WeaponData.DamageType.PROJECTILE and d.splash_radius > 0.0:
		_stat_row("Splash", "%.0f dmg · %.1f m radius" % [d.splash_damage, d.splash_radius])

	for c in _bars.get_children():
		c.queue_free()
	_bar_row("DAMAGE", per_shot / float(_max.get("dmg", 1.0)), Color(1.0, 0.55, 0.4))
	_bar_row("FIRE RATE", d.fire_rate / float(_max.get("rof", 1.0)), Color(1.0, 0.85, 0.4))
	_bar_row("MAGAZINE", float(d.mag_size) / float(_max.get("mag", 1.0)), Color(0.5, 0.85, 1.0))
	_bar_row("RANGE", d.range_m / float(_max.get("rng", 1.0)), Color(0.6, 0.9, 0.6))

	for i in _list_btns.size():
		var on := i == _index
		_list_btns[i].add_theme_color_override("font_color",
			Color(1, 1, 1) if on else (_weapons[i]["data"] as WeaponData).tracer_color.lerp(Color.WHITE, 0.3))
		_list_btns[i].modulate = Color(1, 1, 1, 1.0 if on else 0.7)

	_show_model(_weapons[_index]["path"])

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		_step(1)
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		_step(-1)
