class_name VisionScanner
# @lat: [[level-system#Vision Scanners]]
extends Node3D
## A surveillance "vision model": a sweeping spotlight on a mast. Hold the
## player in its cone for `detect_time` seconds (with a clear line of sight) and
## it raises the alarm, pouring in its authored reinforcement squad, then locks
## onto the player for a few seconds before a cooldown while it "retrains". Shoot
## the head out to blind it for good. Robots are ignored: it only hunts humans.
##
## The level builder wires `alarm` (Callable taking the enemy-spec Array) to its
## reinforcement spawner; tests/scanner_probe drives it with a stub.

signal alarmed

enum Mode { SWEEP, TRACK, COOLDOWN, DEAD }

@export var sweep_deg: float = 90.0     ## total arc swept either side of centre; 360 = full turn
@export var period: float = 7.0         ## seconds for one pass across the arc
@export var cone_deg: float = 11.0      ## half-angle of the detection cone
@export var reach: float = 22.0         ## detection range (m)
@export var tilt_deg: float = 24.0      ## how far the head looks down
@export var detect_time: float = 0.7
@export var track_time: float = 4.0
@export var cooldown: float = 9.0
@export var max_alarms: int = 2
@export var mast: bool = true           ## build a mast from the floor up to the head
@export var alarm_specs: Array = []

const BEAM_SHADER := preload("res://shaders/scanner_beam.gdshader")
const EYE := Color(0.35, 0.85, 1.0)
const WARN := Color(1.0, 0.7, 0.15)
const ALERT := Color(1.0, 0.12, 0.08)

var alarm: Callable
var mode: int = Mode.SWEEP
var exposure: float = 0.0
var alarms_fired: int = 0
var _t: float = 0.0
var _mode_t: float = 0.0
var _pivot: Node3D
var _spot: SpotLight3D
var _cone_mat: ShaderMaterial
var _lens_mat: StandardMaterial3D
var _head_body: StaticBody3D
var _tick_t: float = 0.0
var _base_yaw: float = 0.0

func _ready() -> void:
	add_to_group("scanner")
	_base_yaw = rotation.y
	_build()

func _build() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.11, 0.12, 0.14)
	metal.metallic = 0.8
	metal.roughness = 0.35
	if mast and position.y > 0.6:
		var pole := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.12
		pm.bottom_radius = 0.2
		pm.height = position.y
		pm.radial_segments = 8
		pole.mesh = pm
		pole.material_override = metal
		pole.position.y = -position.y * 0.5
		add_child(pole)
		var foot := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = 0.35
		fm.bottom_radius = 0.5
		fm.height = 0.3
		fm.radial_segments = 8
		foot.mesh = fm
		foot.material_override = metal
		foot.position.y = -position.y + 0.15
		add_child(foot)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.22
		cyl.height = position.y - 0.4
		cs.shape = cyl
		cs.position.y = -position.y * 0.5 - 0.2
		body.add_child(cs)
		add_child(body)

	_pivot = Node3D.new()
	add_child(_pivot)
	var tilt := Node3D.new()
	tilt.rotation.x = -deg_to_rad(tilt_deg)
	_pivot.add_child(tilt)

	# The head: a camera housing with a glowing lens looking down -Z.
	var housing := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.5, 0.42, 0.8)
	housing.mesh = hm
	housing.material_override = metal
	tilt.add_child(housing)
	var lens := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.16
	lm.bottom_radius = 0.16
	lm.height = 0.08
	lens.mesh = lm
	_lens_mat = StandardMaterial3D.new()
	_lens_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lens_mat.emission_enabled = true
	_lens_mat.emission_energy_multiplier = 4.0
	lens.material_override = _lens_mat
	lens.rotation.x = PI * 0.5
	lens.position.z = -0.42
	tilt.add_child(lens)

	# Shootable: the head carries the Damageable, on the world layer so hitscan lands.
	_head_body = StaticBody3D.new()
	_head_body.collision_layer = 1
	_head_body.collision_mask = 0
	var hcs := CollisionShape3D.new()
	var hbs := BoxShape3D.new()
	hbs.size = Vector3(0.7, 0.6, 1.0)
	hcs.shape = hbs
	_head_body.add_child(hcs)
	tilt.add_child(_head_body)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 80.0
	_head_body.add_child(hp)
	hp.died.connect(_on_destroyed)

	_spot = SpotLight3D.new()
	_spot.spot_range = reach
	_spot.spot_angle = cone_deg
	_spot.light_energy = 6.0
	_spot.shadow_enabled = false
	_spot.position.z = -0.45
	tilt.add_child(_spot)

	# Visible beam: an additive cone from the lens out to the detection range.
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = tan(deg_to_rad(cone_deg)) * reach
	cm.height = reach
	cm.radial_segments = 20
	cm.cap_top = false
	cm.cap_bottom = false
	cone.mesh = cm
	_cone_mat = ShaderMaterial.new()
	_cone_mat.shader = BEAM_SHADER
	cone.material_override = _cone_mat
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Cylinder axis +Y onto +Z, so the narrow top lands at the lens and the wide
	# bottom at full reach (-PI/2 put the 4 m mouth on the head itself).
	cone.rotation.x = PI * 0.5
	cone.position.z = -0.45 - reach * 0.5
	tilt.add_child(cone)
	_set_color(EYE, 0.09)

func _set_color(c: Color, cone_alpha: float) -> void:
	_spot.light_color = c
	_lens_mat.albedo_color = c
	_lens_mat.emission = c
	_cone_mat.set_shader_parameter("tint", c)
	_cone_mat.set_shader_parameter("strength", cone_alpha)

## World-space looking direction of the head.
func look_dir() -> Vector3:
	return -_spot.global_transform.basis.z.normalized()

func eye_pos() -> Vector3:
	return _spot.global_position

func _process(delta: float) -> void:
	if mode == Mode.DEAD:
		return
	_t += delta
	_mode_t += delta
	var player := get_tree().get_first_node_in_group("player") as Node3D
	match mode:
		Mode.SWEEP:
			_sweep()
			var seen := player != null and _sees(player)
			exposure = clampf(exposure + (delta if seen else -delta * 0.8), 0.0, detect_time)
			var k := exposure / detect_time
			_set_color(EYE.lerp(WARN, k) if k < 0.999 else ALERT, 0.09 + k * 0.08)
			if seen:
				_tick_t -= delta
				if _tick_t <= 0.0:
					_tick_t = 0.18
					AudioBus.play_synth_at("broadcast_blip", eye_pos(), -6.0, 1.0 + k * 0.8)
					GameState.teach_once("scanner",
						"VISION SCANNER: stay out of its sweep or it calls reinforcements. Shoot the head to blind it.")
			if exposure >= detect_time:
				_raise_alarm()
		Mode.TRACK:
			if player:
				_face(player.global_position + Vector3.UP * 1.2, delta * 4.0)
			var strobe := 0.5 + 0.5 * sin(_t * 18.0)
			_set_color(ALERT, 0.06 + strobe * 0.1)
			if _mode_t >= track_time:
				_set_mode(Mode.COOLDOWN)
		Mode.COOLDOWN:
			_sweep()
			_set_color(EYE.darkened(0.6), 0.015)
			if _mode_t >= cooldown:
				_set_mode(Mode.SWEEP)

func _set_mode(m: int) -> void:
	mode = m
	_mode_t = 0.0
	exposure = 0.0

func _sweep() -> void:
	var a: float
	if sweep_deg >= 359.0:
		a = fmod(_t / period, 1.0) * TAU
	else:
		# Smooth back-and-forth: eases at each end like a real pan head.
		a = sin(_t / period * PI) * deg_to_rad(sweep_deg * 0.5)
	_pivot.rotation.y = lerp_angle(_pivot.rotation.y, a, 0.25)

func _face(target: Vector3, weight: float) -> void:
	var local := to_local(target)
	var want := atan2(-local.x, -local.z)
	_pivot.rotation.y = lerp_angle(_pivot.rotation.y, want, clampf(weight, 0.0, 1.0))

## The player's chest is inside the cone, in range, and nothing solid is between.
func _sees(player: Node3D) -> bool:
	var eye := eye_pos()
	var chest := player.global_position + Vector3.UP * 1.1
	var to := chest - eye
	var d := to.length()
	if d > reach or d < 0.1:
		return false
	if rad_to_deg(look_dir().angle_to(to / d)) > cone_deg:
		return false
	var q := PhysicsRayQueryParameters3D.create(eye, chest, 1)
	q.exclude = [_head_body.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _raise_alarm() -> void:
	_set_mode(Mode.TRACK)
	if alarms_fired >= max_alarms:
		return
	alarms_fired += 1
	alarmed.emit()
	AudioBus.play_synth_at("overlord_glitch", eye_pos(), 4.0, 0.6)
	GameState.skirmish_event.emit("DETECTED", "The vision model flagged you. Reinforcements inbound.")
	if alarm.is_valid() and not alarm_specs.is_empty():
		alarm.call(alarm_specs)

func _on_destroyed(_source) -> void:
	mode = Mode.DEAD
	_spot.visible = false
	_cone_mat.set_shader_parameter("strength", 0.0)
	_lens_mat.albedo_color = Color(0.05, 0.05, 0.05)
	_lens_mat.emission = Color(0.2, 0.05, 0.02)
	_lens_mat.emission_energy_multiplier = 0.5
	_pivot.rotation.x = 0.0
	# Slump the dead head and spit a few sparks' worth of noise.
	create_tween().tween_property(_pivot, "rotation:x", -0.7, 0.4).set_trans(Tween.TRANS_BOUNCE)
	AudioBus.play_synth_at("impact_metal", eye_pos(), 2.0, 0.6)
	GameState.skirmish_event.emit("SCANNER BLINDED", "One less eye on you.")