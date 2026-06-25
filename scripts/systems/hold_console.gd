class_name HoldConsole
extends Area3D
## An interaction point the player must stand at and hold for a few seconds —
## "hacking a terminal" or "planting a charge". Progress accrues while the
## player is in the zone and ebbs slowly if they step away (so it pressures them
## to hold ground under fire). Completes the task at `hold_seconds`; if
## `detonate` is set (sabotage), it blows up on completion.

@export var task_id: String = "hack"
@export var hold_seconds: float = 3.0
@export var detonate: bool = false
@export var accent: Color = Color(0.3, 0.9, 1.0)

const EXPLOSION := preload("res://scenes/fx/grenade_explosion.tscn")

var _done: bool = false
var _inside: int = 0
var _t: float = 0.0
var _panel_mat: StandardMaterial3D  ## pulsing accent frame (terminal) / detonator beacon (bomb)
var _matrix_mat: ShaderMaterial     ## the matrix-rain screen itself (terminal only)
var _charge_label: Label3D          ## bomb arm-countdown readout (detonate only)
var _light: OmniLight3D
var _holo: MeshInstance3D
var _holo_mat: StandardMaterial3D

func _ready() -> void:
	collision_layer = 64
	collision_mask = 2 # player
	add_to_group("objective")
	add_to_group("console")
	body_entered.connect(func(b): if b.is_in_group("player"): _inside += 1)
	body_exited.connect(func(b): if b.is_in_group("player"): _inside = maxi(0, _inside - 1))
	_build_visual()

func _build_visual() -> void:
	if detonate:
		_build_bomb()
	else:
		_build_terminal()

	# Trigger zone (a slab the player stands in/at) — shared.
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.4, 2.0, 2.4)
	cs.shape = bs
	cs.position = Vector3(0, 1.0, 0)
	add_child(cs)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.2, 0.12) if detonate else accent
	_light.light_energy = 2.0
	_light.omni_range = 5.0
	_light.position = Vector3(0, 1.2, 0)
	add_child(_light)

## The hack/terminal "mainframe": matrix-rain screen in a pulsing accent bezel.
func _build_terminal() -> void:
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 1.1, 0.6)
	base.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.13, 0.14, 0.17)
	bmat.metallic = 0.6
	bmat.roughness = 0.4
	base.material_override = bmat
	base.position = Vector3(0, 0.55, 0)
	add_child(base)

	# Angled mainframe monitor: a matrix-rain screen inside a pulsing accent frame.
	var monitor := Node3D.new()
	monitor.position = Vector3(0, 1.22, 0.0)
	monitor.rotation_degrees = Vector3(-28, 0, 0)
	add_child(monitor)
	var sw := 1.12
	var sh := 0.82
	# The screen — digital rain in the level's accent, nudged toward matrix-green.
	var panel := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(sw, sh, 0.05)
	panel.mesh = pm
	_matrix_mat = MatrixScreen.material(accent.lerp(Color(0.25, 1.0, 0.4), 0.4), 2.8)
	panel.material_override = _matrix_mat
	monitor.add_child(panel)
	# A glowing bezel of four bars (this is what the pulse drives now).
	_panel_mat = StandardMaterial3D.new()
	_panel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_panel_mat.albedo_color = accent
	_panel_mat.emission_enabled = true
	_panel_mat.emission = accent
	_panel_mat.emission_energy_multiplier = 2.5
	var ft := 0.06
	for bar in [
			[Vector3(0, sh * 0.5 + ft * 0.5, 0), Vector3(sw + ft * 2.0, ft, 0.07)],
			[Vector3(0, -sh * 0.5 - ft * 0.5, 0), Vector3(sw + ft * 2.0, ft, 0.07)],
			[Vector3(-sw * 0.5 - ft * 0.5, 0, 0), Vector3(ft, sh, 0.07)],
			[Vector3(sw * 0.5 + ft * 0.5, 0, 0), Vector3(ft, sh, 0.07)]]:
		var fb := MeshInstance3D.new()
		var fbm := BoxMesh.new()
		fbm.size = bar[1]
		fb.mesh = fbm
		fb.material_override = _panel_mat
		fb.position = bar[0]
		monitor.add_child(fb)

	# A holographic data prism projected above the console — clearly an active
	# terminal beaming something, not just a lit box.
	_holo_mat = StandardMaterial3D.new()
	_holo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_holo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_holo_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.55)
	_holo_mat.emission_enabled = true
	_holo_mat.emission = accent
	_holo_mat.emission_energy_multiplier = 3.0
	_holo = MeshInstance3D.new()
	var pr := PrismMesh.new()
	pr.size = Vector3(0.5, 0.7, 0.5)
	_holo.mesh = pr
	_holo.material_override = _holo_mat
	_holo.position = Vector3(0, 1.95, 0)
	_holo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_holo)

## The sabotage "plant the bomb" device: a hazard-striped demolition charge with
## a blinking red detonator beacon and a live arm-time countdown readout.
func _build_bomb() -> void:
	var det := Color(1.0, 0.22, 0.12)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.1, 0.12)
	dark.metallic = 0.5
	dark.roughness = 0.5
	# Charge body.
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.15, 0.7, 0.78)
	body.mesh = bm
	body.material_override = dark
	body.position = Vector3(0, 0.5, 0)
	add_child(body)
	# Yellow/black hazard bands wrapping the charge.
	var haz := StandardMaterial3D.new()
	haz.albedo_color = Color(0.95, 0.72, 0.05)
	haz.emission_enabled = true
	haz.emission = Color(0.9, 0.6, 0.0)
	haz.emission_energy_multiplier = 0.4
	for hy in [0.33, 0.67]:
		var band := MeshInstance3D.new()
		var hbm := BoxMesh.new()
		hbm.size = Vector3(1.17, 0.12, 0.8)
		band.mesh = hbm
		band.material_override = haz
		band.position = Vector3(0, hy, 0)
		add_child(band)
	# Detonator beacon dome on top (this is what the pulse blinks → _panel_mat).
	_panel_mat = StandardMaterial3D.new()
	_panel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_panel_mat.albedo_color = det
	_panel_mat.emission_enabled = true
	_panel_mat.emission = det
	_panel_mat.emission_energy_multiplier = 3.0
	var beacon := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.12
	sp.height = 0.24
	beacon.mesh = sp
	beacon.material_override = _panel_mat
	beacon.position = Vector3(0, 0.95, 0)
	add_child(beacon)
	# Stub antenna.
	var ant := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = 0.4
	ant.mesh = cyl
	ant.material_override = dark
	ant.position = Vector3(0.42, 1.05, 0)
	add_child(ant)
	# Floating arm-time countdown (billboarded so it always faces the player).
	_charge_label = Label3D.new()
	_charge_label.text = "%0.1f" % hold_seconds
	_charge_label.font_size = 110
	_charge_label.pixel_size = 0.004
	_charge_label.modulate = det
	_charge_label.outline_size = 14
	_charge_label.outline_modulate = Color(0, 0, 0, 0.9)
	_charge_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_charge_label.position = Vector3(0, 1.45, 0)
	add_child(_charge_label)
	_holo = null # no data prism on the bomb

func _process(delta: float) -> void:
	_t += delta
	var prog := _task_progress()
	if not _done:
		if _inside > 0:
			GameState.advance_task(task_id, delta)
			if GameState.is_task_done(task_id):
				_on_complete()
		elif prog > 0.0:
			GameState.set_task_progress(task_id, maxf(0.0, prog - delta * 0.5))
	# Bomb: blink the detonator faster + tick the arm-countdown down as it's planted.
	if detonate:
		if _done:
			return
		var remaining: float = maxf(0.0, hold_seconds * (1.0 - prog))
		var urgency: float = 1.0 - clampf(remaining / maxf(hold_seconds, 0.01), 0.0, 1.0)
		var blink: float = 0.5 + 0.5 * signf(sin(_t * (4.0 + urgency * 18.0)))
		if _panel_mat:
			_panel_mat.emission_energy_multiplier = 0.8 + blink * (2.5 + urgency * 4.5)
		if _light:
			_light.light_energy = 0.7 + blink * (2.0 + urgency * 3.0)
		if _charge_label:
			_charge_label.text = "%0.1f" % remaining
			_charge_label.modulate = Color(1.0, 0.28, 0.12).lerp(Color(1, 1, 1), blink * urgency * 0.6)
		return
	# Faster pulse while actively being worked.
	var rate := 9.0 if _inside > 0 and not _done else 3.0
	if _panel_mat:
		_panel_mat.emission_energy_multiplier = 2.5 + sin(_t * rate) * 1.2
	if _matrix_mat and not _done:
		# Code rains harder/brighter while the terminal is being worked.
		_matrix_mat.set_shader_parameter("emission_energy", 4.4 if _inside > 0 else 2.8)
	if _light:
		_light.light_energy = 2.0 + sin(_t * rate) * 0.8
	if _holo:
		_holo.rotate_object_local(Vector3.UP, delta * (3.0 if _inside > 0 and not _done else 1.2))
		_holo.position.y = 1.95 + sin(_t * 2.0) * 0.06

## Current progress value of our task (0 if missing).
func _task_progress() -> float:
	for t in GameState.level_tasks:
		if t["id"] == task_id:
			return t["progress"]
	return 0.0

func _on_complete() -> void:
	_done = true
	if has_node("/root/AudioBus"):
		var ab: Node = get_node("/root/AudioBus")
		if ab.has_method("play_synth_at"):
			ab.play_synth_at("pickup_health", global_position, -1.0, 0.9)
	if detonate:
		var fx := EXPLOSION.instantiate()
		get_parent().add_child(fx)
		(fx as Node3D).global_position = global_position + Vector3.UP * 1.0
		(fx as Node3D).scale = Vector3.ONE * 1.5
		var p := get_tree().get_first_node_in_group("player")
		if p and p.has_method("shake"):
			p.shake(0.6)
		queue_free()
	else:
		# Hacked terminal goes dim/green and inert — the code rain fades out.
		if _panel_mat:
			_panel_mat.emission = Color(0.3, 1.0, 0.4)
		if _matrix_mat:
			_matrix_mat.set_shader_parameter("rain_color", Vector3(0.2, 0.7, 0.3))
			_matrix_mat.set_shader_parameter("emission_energy", 0.7)
