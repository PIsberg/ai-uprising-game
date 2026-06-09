class_name BossTelegraph
extends Node3D
## Set-piece: a colossal dark silhouette looming on the horizon beyond the arena
## wall, with blazing red eyes, distant alarms and ground rumbles — telegraphing
## the boss before the player crosses the plaza and triggers the real fight.
## Pure set dressing (no collision); built procedurally from boxes.

@export var figure_pos: Vector3 = Vector3(0, 0, -72)
@export var figure_height: float = 22.0
@export var face_point: Vector3 = Vector3.ZERO

var _eye_mat: StandardMaterial3D
var _eyes: Array[OmniLight3D] = []
var _figure: Node3D
var _t: float = 0.0

func _ready() -> void:
	_build_figure()
	_intro.call_deferred()

func _build_figure() -> void:
	_figure = Node3D.new()
	_figure.position = figure_pos
	add_child(_figure)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.02, 0.035)
	dark.roughness = 1.0
	var h := figure_height
	_add_part(Vector3(-h * 0.09, h * 0.21, 0), Vector3(h * 0.1, h * 0.42, h * 0.1), dark)   # leg L
	_add_part(Vector3(h * 0.09, h * 0.21, 0), Vector3(h * 0.1, h * 0.42, h * 0.1), dark)    # leg R
	_add_part(Vector3(0, h * 0.55, 0), Vector3(h * 0.36, h * 0.34, h * 0.22), dark)         # torso
	_add_part(Vector3(-h * 0.26, h * 0.6, 0), Vector3(h * 0.12, h * 0.32, h * 0.12), dark)  # arm L
	_add_part(Vector3(h * 0.26, h * 0.6, 0), Vector3(h * 0.12, h * 0.32, h * 0.12), dark)   # arm R
	_add_part(Vector3(0, h * 0.82, 0), Vector3(h * 0.17, h * 0.15, h * 0.17), dark)         # head
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.emission_enabled = true
	_eye_mat.albedo_color = Color(1, 0.12, 0.06)
	_eye_mat.emission = Color(1, 0.12, 0.06)
	_eye_mat.emission_energy_multiplier = 6.0
	var ey := h * 0.83
	var ez := -h * 0.09 # front face (-Z)
	_make_eye(Vector3(-h * 0.045, ey, ez))
	_make_eye(Vector3(h * 0.045, ey, ez))
	# Turn the figure's front (-Z) toward the arena.
	var dir := (face_point - figure_pos)
	dir.y = 0.0
	if dir.length() > 0.01:
		dir = dir.normalized()
		_figure.rotation.y = atan2(-dir.x, -dir.z)

func _add_part(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	_figure.add_child(mi)

func _make_eye(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = figure_height * 0.03
	sm.height = figure_height * 0.06
	mi.mesh = sm
	mi.material_override = _eye_mat
	mi.position = pos
	_figure.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.15, 0.08)
	light.light_energy = 2.0
	light.omni_range = figure_height * 0.5
	light.position = pos
	_figure.add_child(light)
	_eyes.append(light)

func _process(delta: float) -> void:
	_t += delta
	var pulse := 4.0 + sin(_t * 2.0) * 3.0
	if _eye_mat:
		_eye_mat.emission_energy_multiplier = pulse
	for e in _eyes:
		e.light_energy = 1.4 + sin(_t * 2.0) * 1.0
	if _figure:
		_figure.position.y = figure_pos.y + sin(_t * 0.6) * 0.4 # slow ominous heave

func _intro() -> void:
	await get_tree().create_timer(0.6).timeout
	var p := get_tree().get_first_node_in_group("player")
	AudioBus.play_synth_ui("eas_alert", -12.0)
	if p and p.has_method("notify_pickup"):
		p.notify_pickup("⚠ COLOSSUS DETECTED — MAPLE GROVE")
	for i in 3:
		await get_tree().create_timer(1.5).timeout
		if not is_inside_tree() or _figure == null:
			return
		AudioBus.play_synth_at("explosion", _figure.global_position, -4.0, 0.4)
		var pl := get_tree().get_first_node_in_group("player")
		if pl and pl.has_method("shake"):
			pl.shake(0.22)
