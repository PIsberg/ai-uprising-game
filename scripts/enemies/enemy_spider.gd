class_name EnemySpider
extends EnemyBase
## Medium, fast, ground-hugging spider drone. Scuttles up to the player and bites
## in melee with a short lunge. Legs are generated + animated procedurally.

@export var bite_damage: float = 20.0
@export var lunge_speed: float = 13.5
@export var leg_count: int = 8
@export var leg_attach_y: float = 0.42

@export_group("Leap")
@export var leap_windup: float = 0.45 ## Telegraph time before it springs (your window to shoot).
@export var leap_cooldown: float = 3.2
@export var leap_min: float = 4.0 ## Won't leap closer than this…
@export var leap_max: float = 16.0 ## …or further than this.
@export var leap_h_speed: float = 13.0
@export var leap_up: float = 7.5

const LEG_MAT := preload("res://assets/materials/metal_dark.tres")

var _legs: Array[Node3D] = []
var _leg_rest: Array[Vector3] = []
var _gait: float = 0.0
var _glow_mat: StandardMaterial3D
var _leaping: bool = false
var _leap_time: float = 0.0
var _windup: float = 0.0
var _leap_cd: float = 0.0


func _ready() -> void:
	super._ready()
	# Fragile glass-cannon: a single well-timed shot drops it — the challenge is
	# tracking it through its leap, not out-damaging it.
	max_health = 24.0
	move_speed = 8.2
	turn_speed = 11.0
	sight_range = 34.0
	sight_angle_deg = 300.0 # many eyes — near-omnidirectional awareness
	attack_range = 2.6
	preferred_range = 1.3
	attack_cooldown = 0.8
	score_value = 120
	hp.max_health = max_health
	hp.current_health = max_health
	_build_legs()
	
	_glow_mat = preload("res://assets/materials/glow_red.tres").duplicate() as StandardMaterial3D
	$EyeL.material_override = _glow_mat
	$EyeR.material_override = _glow_mat
	$EyeC.material_override = _glow_mat


func _build_legs() -> void:
	var per_side := leg_count / 2
	for i in leg_count:
		var side := 1.0 if i < per_side else -1.0
		var idx := i % per_side
		var yaw := deg_to_rad((55.0 + idx * 30.0) * side)
		var pivot := Node3D.new()
		pivot.name = "Leg%d" % i
		pivot.position = Vector3(0, leg_attach_y, 0)
		pivot.rotation = Vector3(0, yaw, 0)
		add_child(pivot)
		var cap := MeshInstance3D.new()
		var m := CapsuleMesh.new()
		m.radius = 0.035
		m.height = 0.72
		m.material = LEG_MAT
		cap.mesh = m
		# Tilt the leg down-and-outward (local -Z is outward) to a foot.
		cap.rotation = Vector3(deg_to_rad(-135.0), 0, 0)
		cap.position = Vector3(0, -0.26, -0.26)
		pivot.add_child(cap)
		_legs.append(pivot)
		_leg_rest.append(pivot.rotation)

# Leap-pounce: scuttles up, crouches into a brief telegraphed windup, then springs
# in a ballistic arc at the player. The whole pounce is the threat — and the shot
# window. Falls back to the base ground AI when not leaping.
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_leap_cd = maxf(0.0, _leap_cd - delta)
	if _leaping:
		_apply_gravity(delta)
		move_and_slide()
		_leap_time += delta
		if (is_on_floor() and _leap_time > 0.2) or _leap_time > 2.5:
			_leaping = false
			_leap_cd = leap_cooldown
			_bite_if_close()
		return
	if _windup > 0.0:
		_windup -= delta
		_decelerate()
		_face_target(delta)
		_apply_gravity(delta)
		move_and_slide()
		if _windup <= 0.0:
			_launch_leap()
		return
	super._physics_process(delta)
	# Consider springing from range.
	if target and _leap_cd <= 0.0 and is_on_floor():
		var dist := global_position.distance_to(target.global_position)
		if dist >= leap_min and dist <= leap_max and _can_see(target):
			_begin_windup()

func _begin_windup() -> void:
	_windup = leap_windup
	AudioBus.play_synth_at("broadcast_blip", global_position, -2.0, 0.6)

func _launch_leap() -> void:
	if target == null:
		return
	_leaping = true
	_leap_time = 0.0
	var dir := target.global_position - global_position
	dir.y = 0.0
	dir = dir.normalized()
	velocity.x = dir.x * leap_h_speed
	velocity.z = dir.z * leap_h_speed
	velocity.y = leap_up
	AudioBus.play_synth_at("mech_step", global_position, 0.0, 1.6)

func _bite_if_close() -> void:
	if target == null:
		return
	if global_position.distance_to(target.global_position) <= attack_range * 1.6:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(bite_damage, self)
		AudioBus.play_synth_at("impact_metal", global_position, -1.0, 1.4)

func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	# Scuttle: alternating legs (rough tripod gait) bob faster as it moves.
	var speed := Vector2(velocity.x, velocity.z).length()
	_gait += delta * (7.0 + speed * 2.2)
	# Tuck legs in mid-leap; otherwise normal gait.
	var amp := clampf(speed / move_speed, 0.0, 1.0) * 0.45 + 0.04
	for i in _legs.size():
		var ph := _gait + (0.0 if i % 2 == 0 else PI)
		var tuck := 0.5 if _leaping else 0.0
		_legs[i].rotation = _leg_rest[i] + Vector3(sin(ph) * amp + tuck, 0, 0)
	if _glow_mat:
		# Eyes flare bright during the windup — the tell to time your shot.
		if _windup > 0.0:
			_glow_mat.emission_energy_multiplier = 14.0
		else:
			_glow_mat.emission_energy_multiplier = 4.0 + sin(_gait * 3.0) * 1.5


func _perform_attack() -> void:
	if target == null:
		return
	if global_position.distance_to(target.global_position) <= attack_range:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(bite_damage, self)
		# Quick forward lunge on the bite.
		var dir := target.global_position - global_position
		dir.y = 0.0
		dir = dir.normalized()
		velocity.x = dir.x * lunge_speed
		velocity.z = dir.z * lunge_speed
		AudioBus.play_synth_at("impact_metal", global_position, -1.0, 1.4)
