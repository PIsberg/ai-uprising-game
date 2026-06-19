class_name EnemyVacuum
extends EnemyBase
## "Custodian" cleaning unit. Idles as a low disc trundling along the floor,
## vacuuming. The instant it senses the player — or takes a hit — it shudders,
## unfolds four legs and rears up into a hostile walker, then chases and fires
## energy bolts. Built entirely from procedural primitives so the transform can
## be animated in code.

enum Phase { GROUND, RISING, COMBAT }

@export var wake_range: float = 13.0
@export var rise_duration: float = 1.4
@export var rise_height: float = 0.95
@export var ground_speed: float = 2.6
@export var proj_speed: float = 40.0
@export var proj_damage: float = 9.0
@export var burst_count: int = 2

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")

var _phase: int = Phase.GROUND
var _rise_t: float = 0.0
var _chassis: Node3D
var _legs: Array[Node3D] = []
var _eye_mat: StandardMaterial3D
var _wander: Vector3 = Vector3.FORWARD
var _wander_cd: float = 0.0
var _burst_left: int = 0
var _burst_t: float = 0.0


func _ready() -> void:
	max_health = 95.0
	move_speed = 6.5            # combat walk speed (once risen)
	turn_speed = 7.0
	sight_range = 30.0
	sight_angle_deg = 230.0
	attack_range = 22.0
	preferred_range = 12.0
	attack_cooldown = 1.4
	score_value = 110
	stagger_threshold = 60.0
	super._ready()
	_build_model()
	_apply_rise(0.0)


func _build_model() -> void:
	var model: Node3D = get_node_or_null("Model")
	if model == null:
		model = Node3D.new()
		model.name = "Model"
		add_child(model)
	_chassis = Node3D.new()
	_chassis.name = "Chassis"
	model.add_child(_chassis)

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.72, 0.74, 0.77)
	body_mat.metallic = 0.6
	body_mat.roughness = 0.4
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.11, 0.11, 0.13)
	dark.metallic = 0.7
	dark.roughness = 0.5
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(0.2, 0.9, 1.0)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(0.2, 0.9, 1.0)
	_eye_mat.emission_energy_multiplier = 1.2

	# Disc body (the vacuum-cleaner chassis).
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.52
	dm.bottom_radius = 0.58
	dm.height = 0.2
	dm.material = body_mat
	disc.mesh = dm
	disc.position.y = 0.12
	_chassis.add_child(disc)

	# Dark bumper ring around the rim.
	var ring := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.6
	rm.bottom_radius = 0.6
	rm.height = 0.06
	rm.material = dark
	ring.mesh = rm
	ring.position.y = 0.19
	_chassis.add_child(ring)

	# Sensor dome / glowing eye on the forward edge.
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.26
	sm.material = _eye_mat
	dome.mesh = sm
	dome.position = Vector3(0, 0.26, -0.18)
	_chassis.add_child(dome)

	# Four folded legs that unfold and lock vertical when it rises.
	for i in 4:
		var ang := PI * 0.25 + float(i) * PI * 0.5
		var pivot := Node3D.new()
		pivot.position = Vector3(cos(ang) * 0.5, 0.12, sin(ang) * 0.5)
		_chassis.add_child(pivot)
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.08, 0.55, 0.08)
		lm.material = dark
		leg.mesh = lm
		leg.position = Vector3(0, -0.27, 0)   # extends down from the pivot
		pivot.add_child(leg)
		pivot.rotation = Vector3(0, ang, PI * 0.5)  # folded flat under the disc
		_legs.append(pivot)


## t: 0 = folded disc flat on the ground, 1 = reared up standing on its legs.
func _apply_rise(t: float) -> void:
	t = clampf(t, 0.0, 1.0)
	var e := t * t * (3.0 - 2.0 * t)  # smoothstep
	if _chassis:
		_chassis.position.y = e * rise_height
	for i in _legs.size():
		var ang := PI * 0.25 + float(i) * PI * 0.5
		_legs[i].rotation = Vector3(0, ang, lerpf(PI * 0.5, 0.0, e))
	if _eye_mat:
		_eye_mat.emission_energy_multiplier = lerpf(1.2, 3.6, e)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	match _phase:
		Phase.GROUND:
			_ground_tick(delta)
		Phase.RISING:
			_rising_tick(delta)
		Phase.COMBAT:
			super._physics_process(delta)
			_combat_fire(delta)


func _ground_tick(delta: float) -> void:
	_perceive()
	if target and is_instance_valid(target):
		var d := global_position.distance_to(target.global_position)
		if d <= wake_range and _can_see(target):
			_begin_rise()
			return
	# Slow cleaning wander.
	_wander_cd -= delta
	if _wander_cd <= 0.0:
		_wander_cd = randf_range(1.5, 3.0)
		var a := randf() * TAU
		_wander = Vector3(cos(a), 0.0, sin(a))
	velocity.x = _wander.x * ground_speed
	velocity.z = _wander.z * ground_speed
	_face_dir(_wander, delta)
	_apply_gravity(delta)
	move_and_slide()


func _begin_rise() -> void:
	if _phase != Phase.GROUND:
		return
	_phase = Phase.RISING
	_rise_t = 0.0
	velocity = Vector3.ZERO
	AudioBus.play_synth_at("drone_hum", global_position, -1.0, 0.8)
	_speak("atk", 0.6)


func _rising_tick(delta: float) -> void:
	_rise_t += delta / maxf(0.1, rise_duration)
	if _chassis:
		_chassis.position.x = sin(_rise_t * 38.0) * 0.03 * (1.0 - clampf(_rise_t, 0.0, 1.0))
	_apply_rise(_rise_t)
	_apply_gravity(delta)
	move_and_slide()
	if _rise_t >= 1.0:
		if _chassis:
			_chassis.position.x = 0.0
		_phase = Phase.COMBAT
		set_state(State.CHASE)


func _combat_fire(delta: float) -> void:
	if _burst_left > 0:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_fire_one()
			_burst_left -= 1
			_burst_t = 0.12


func _perform_attack() -> void:
	if target == null or _burst_left > 0:
		return
	_burst_left = burst_count
	_burst_t = 0.0


func _fire_one() -> void:
	if target == null or not is_instance_valid(target):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var origin: Vector3 = muzzle.global_position if muzzle else global_position + Vector3.UP
	var proj := PROJECTILE.instantiate()
	scene.add_child(proj)
	(proj as Node3D).global_position = origin
	var dir := (target.global_position + Vector3.UP * 0.5 - origin).normalized()
	dir = scatter_aim(dir, 3.0)
	if proj.has_method("launch"):
		proj.launch(dir * proj_speed, self, proj_damage, 0.0, 0.0)
	recoil = 1.0
	_muzzle_flash()


## Taking fire while still a disc also triggers the rise.
func _on_damaged(amount: float, source: Node) -> void:
	super._on_damaged(amount, source)
	if _phase == Phase.GROUND:
		_begin_rise()
