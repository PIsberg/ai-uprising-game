class_name EnemyShark
extends EnemyDrone
## RAZORFIN — a robotic shark that prowls the flooded basin BELOW the surface,
## showing only a wake as it stalks you along the gantries. When it strikes it
## BREACHES: it rockets up out of the water in an arc, snaps at you mid-leap, and
## crashes back under with a splash. Hard to hit while submerged — punish it at
## the apex of a breach.

@export var surface_y: float = 0.0     ## Water surface height for this level.
@export var submerge_depth: float = 1.7 ## How far below the surface it cruises.
@export var breach_height: float = 3.4  ## Apex height above the surface during a breach.
@export var bite_damage: float = 28.0
@export var bite_reach: float = 3.6

const BREACH_TIME := 1.25

var _breaching: bool = false
var _breach_t: float = 0.0
var _breach_cd: float = 2.0
var _breach_dir: Vector3 = Vector3.FORWARD
var _bit: bool = false
var _prev_y: float = 0.0
@onready var _model_node: Node3D = get_node_or_null("Model")

func _ready() -> void:
	super._ready()
	max_health = 130.0
	move_speed = 7.0
	sight_range = 44.0
	attack_range = 17.0      # state-trigger range; the breach lunges in from here
	preferred_range = 7.0
	attack_cooldown = 0.1
	score_value = 200
	hover_amplitude = 0.25
	hover_freq = 1.4
	drops_loot = true
	hp.max_health = max_health
	hp.current_health = max_health
	_breach_cd = randf_range(1.5, 2.8)
	_prev_y = global_position.y

func _cruise_y() -> float:
	return surface_y - submerge_depth

## Bubbles streaming off it as it swims (replaces the drone's thruster trail).
func _make_exhaust() -> void:
	var p := CPUParticles3D.new()
	p.amount = 18
	p.lifetime = 1.1
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 25.0
	p.gravity = Vector3(0, 1.0, 0)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.7
	var mesh := SphereMesh.new()
	mesh.radius = 0.05; mesh.height = 0.1; mesh.radial_segments = 6; mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.85, 1.0, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.8, 1.0)
	mat.emission_energy_multiplier = 1.2
	mesh.material = mat
	p.mesh = mesh
	p.position = Vector3(0, 0.0, 0.3)
	add_child(p)

## Cruise submerged toward a stalking point under the player; face it; bob gently.
func _move_toward(dest: Vector3, delta: float) -> void:
	_hover_phase += delta * hover_freq
	var desired_y := _cruise_y() + sin(_hover_phase) * hover_amplitude
	var to := dest - global_position
	to.y = 0
	var dir := to.normalized() if to.length() > 0.01 else Vector3.ZERO
	velocity.x = move_toward(velocity.x, dir.x * move_speed, 10.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * move_speed, 10.0 * delta)
	velocity.y = move_toward(velocity.y, (desired_y - global_position.y) * 4.0, 30.0 * delta)
	_face_dir(dir, delta)

func _state_attack(delta: float) -> void:
	if target == null or not _can_see(target):
		set_state(State.CHASE)
		return
	if _breaching:
		_do_breach(delta)
		return
	_breach_cd -= delta
	# Stalk submerged at preferred range until the next breach is ready.
	var to := target.global_position - global_position
	to.y = 0
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else Vector3.ZERO
	var pull := 0.0
	if dist > preferred_range * 1.15:
		pull = 1.0
	elif dist < preferred_range * 0.8:
		pull = -0.7
	_hover_phase += delta * hover_freq
	var desired_y := _cruise_y() + sin(_hover_phase) * hover_amplitude
	velocity.x = move_toward(velocity.x, dir.x * move_speed * pull, 9.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * move_speed * pull, 9.0 * delta)
	velocity.y = move_toward(velocity.y, (desired_y - global_position.y) * 4.0, 30.0 * delta)
	_face_dir(dir, delta)
	if _breach_cd <= 0.0 and dist <= attack_range:
		_start_breach()

func _start_breach() -> void:
	_breaching = true
	_breach_t = 0.0
	_bit = false
	var to := target.global_position - global_position
	to.y = 0
	_breach_dir = to.normalized() if to.length() > 0.01 else -global_transform.basis.z
	velocity = Vector3.ZERO
	_prev_y = global_position.y
	AudioBus.play_synth_at("impact_metal", global_position, -2.0, 0.7)

## The leap: a parabola from the cruise depth up over the surface toward the
## player and back under, snapping once at the top of the arc. Driven by position
## (not velocity) so the launch impulse can't leak into the cruise that follows.
func _do_breach(delta: float) -> void:
	_breach_t += delta
	var u := _breach_t / BREACH_TIME
	if u >= 1.0:
		_breaching = false
		_breach_cd = randf_range(2.2, 3.6)
		velocity = Vector3.ZERO
		if _model_node:
			_model_node.rotation.x = 0.0
		return
	var rise := submerge_depth + breach_height          # total climb from cruise depth
	var desired_y := _cruise_y() + 4.0 * rise * u * (1.0 - u)
	var lunge := move_speed * 1.5 * delta
	global_position += Vector3(_breach_dir.x * lunge, 0.0, _breach_dir.z * lunge)
	global_position.y = desired_y
	velocity = Vector3.ZERO  # motion is scripted; don't let move_and_slide add to it
	_face_dir(_breach_dir, delta * 2.0)
	# Pitch the body to follow the arc — nose up on the climb, down on the dive.
	var climb := desired_y - _prev_y
	if _model_node:
		_model_node.rotation.x = clampf(-climb * 6.0, -0.7, 0.7)
	# Splash when the body crosses the surface (either direction).
	if (_prev_y < surface_y) != (global_position.y < surface_y):
		_splash()
	# Snap at the apex if the player is in reach.
	if not _bit and target and global_position.distance_to(target.global_position) <= bite_reach:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(bite_damage, self)
		_bit = true
		AudioBus.play_synth_at("impact_metal", global_position, -2.0, 1.6)
	_prev_y = global_position.y

## A quick burst of water droplets where it pierces the surface.
func _splash() -> void:
	var p := CPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = 24
	p.lifetime = 0.6
	p.explosiveness = 0.9
	p.direction = Vector3(0, 1, 0)
	p.spread = 55.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -9.0, 0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.06; mesh.height = 0.12; mesh.radial_segments = 6; mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.9, 1.0, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.85, 1.0)
	mat.emission_energy_multiplier = 1.4
	mesh.material = mat
	p.mesh = mesh
	get_parent().add_child(p)
	(p as Node3D).global_position = Vector3(global_position.x, surface_y, global_position.z)
	p.finished.connect(p.queue_free)
	AudioBus.play_synth_at("explosion", Vector3(global_position.x, surface_y, global_position.z), -10.0, 1.8)
