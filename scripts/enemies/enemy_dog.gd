class_name EnemyDog
extends EnemyBase
## K-9 HUNTER — a four-legged robot attack-hound. Very fast, hunts in packs,
## sprints the gap and lunges into a bite. Fragile but relentless. Built model:
## assets/models/robots/robot_dog.glb (RobotModel leans it; no walk rig).
##
## Signature move: the POUNCE. From mid range it plants, rears back with jaws
## wide (a clear half-second tell — your window to shoot it out of the air),
## then springs in a flat arc and snaps its bite on landing.

@export var bite_damage: float = 16.0
@export var pounce_damage: float = 22.0
@export var pounce_windup: float = 0.5
@export var pounce_cooldown: float = 3.5
@export var pounce_min: float = 4.0
@export var pounce_max: float = 11.0
@export var pounce_h_speed: float = 13.0
@export var pounce_up: float = 5.5

var _pouncing: bool = false
var _pounce_t: float = 0.0
var _pounce_windup_t: float = 0.0
var _pounce_cd: float = 0.0

func _ready() -> void:
	max_health = 72.0
	move_speed = 9.2
	turn_speed = 11.0
	sight_range = 38.0
	sight_angle_deg = 230.0
	attack_range = 3.2
	preferred_range = 1.3
	attack_cooldown = 1.0
	attack_lunge_speed = 15.0
	telegraph_time = 0.22
	score_value = 120
	stagger_threshold = 28.0
	super._ready()

## Rear-back → spring → landing bite, layered over the base ground AI the same
## way the ravager's leap is. Airborne and during the windup it's a clean shot.
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_pounce_cd = maxf(0.0, _pounce_cd - delta)
	if _pouncing:
		_apply_gravity(delta)
		move_and_slide()
		_pounce_t += delta
		if (is_on_floor() and _pounce_t > 0.15) or _pounce_t > 1.8:
			_pouncing = false
			_pounce_cd = pounce_cooldown
			_land_bite()
		return
	if _pounce_windup_t > 0.0:
		_pounce_windup_t -= delta
		_decelerate()
		_face_target(delta)
		# Jaws-wide rear-back: pitch the chassis up so the tell reads at range.
		if _visual_root:
			_visual_root.rotation.x = _visual_base_rot.x - 0.55 * minf(1.0, (pounce_windup - _pounce_windup_t) * 4.0)
		_apply_gravity(delta)
		move_and_slide()
		if _pounce_windup_t <= 0.0:
			_launch_pounce()
		return
	super._physics_process(delta)
	if target and _pounce_cd <= 0.0 and is_on_floor() \
			and state in [State.CHASE, State.ATTACK]:
		var dist := global_position.distance_to(target.global_position)
		if dist >= pounce_min and dist <= pounce_max and _can_see(target):
			_pounce_windup_t = pounce_windup
			recoil = 0.6
			AudioBus.play_synth_at("overlord_glitch", global_position, -8.0, 1.9)

func _launch_pounce() -> void:
	if target == null or not is_instance_valid(target):
		return
	_pouncing = true
	_pounce_t = 0.0
	var dir := target.global_position - global_position
	dir.y = 0.0
	dir = dir.normalized()
	velocity = Vector3(dir.x * pounce_h_speed, pounce_up, dir.z * pounce_h_speed)
	recoil = 1.0
	AudioBus.play_synth_at("impact_metal", global_position, -7.0, 2.2)

func _land_bite() -> void:
	if _visual_root:
		_visual_root.rotation.x = _visual_base_rot.x
	if target and is_instance_valid(target) \
			and global_position.distance_to(target.global_position) <= 2.2:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(pounce_damage, self)
		AudioBus.play_synth_at("impact_metal", global_position, -5.0, 1.6)

func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= attack_range * 1.5:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(bite_damage, self)
		AudioBus.play_synth_at("impact_metal", global_position, -6.0, 1.9)
	_attack_lunge()
