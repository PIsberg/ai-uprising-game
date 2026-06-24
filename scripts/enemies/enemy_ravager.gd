class_name EnemyRavager
extends EnemyBase
## RAVAGER — the fierce alpha of the swarm. A heavy, armoured brute that lumbers
## between long, telegraphed leaps, crashing down into a ground-slam that hammers
## everything around the impact. Where a skitter nips at your feet, a Ravager
## bounds the length of the arena and lands on your head — the late-game threat
## that punishes standing still. Tanky and hard to stagger; the windup before
## each leap is your window. Real model: the bladed fierce chassis, scaled up.

@export var slam_damage: float = 26.0
@export var slam_radius: float = 4.2 ## Landing shockwave — clips you even if the leap overshoots.

@export_group("Leap")
@export var leap_windup: float = 0.5 ## It rears back and coils — a clear tell before it springs.
@export var leap_cooldown: float = 2.0
@export var leap_min: float = 4.0
@export var leap_max: float = 18.0
@export var leap_h_speed: float = 14.0
@export var leap_up: float = 7.5

var _leaping: bool = false
var _leap_time: float = 0.0
var _windup: float = 0.0
var _leap_cd: float = 0.0

@onready var _eye_light: OmniLight3D = $EyeLight

func _ready() -> void:
	max_health = 220.0
	move_speed = 4.6
	turn_speed = 7.0
	sight_range = 40.0
	sight_angle_deg = 240.0
	attack_range = 3.6
	preferred_range = 2.0
	attack_cooldown = 1.6
	score_value = 320
	stagger_threshold = 90.0   # an armoured bruiser — won't be stunlocked
	flinch_knockback = 0.3
	super._ready()
	hp.max_health = max_health
	hp.current_health = max_health

## Lumber-then-bound: closes on the player, then telegraphs and springs in a high
## ballistic arc, ground-slamming on landing. Falls back to the base ground AI.
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_leap_cd = maxf(0.0, _leap_cd - delta)
	if _leaping:
		_apply_gravity(delta)
		move_and_slide()
		_leap_time += delta
		if (is_on_floor() and _leap_time > 0.18) or _leap_time > 2.2:
			_leaping = false
			_leap_cd = leap_cooldown
			_slam()
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
	if target and _leap_cd <= 0.0 and is_on_floor() \
			and state in [State.CHASE, State.ATTACK]:
		var dist := global_position.distance_to(target.global_position)
		if dist >= leap_min and dist <= leap_max and _can_see(target):
			_begin_windup()

func _begin_windup() -> void:
	_windup = leap_windup
	recoil = 0.6
	AudioBus.play_synth_at("overlord_glitch", global_position, -5.0, 1.2)

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
	recoil = 1.0
	AudioBus.play_synth_at("impact_metal", global_position, -3.0, 0.8)

## Ground-slam: a heavy AoE thump on landing — hits the player if they're inside
## the shockwave, so leaping into a crowd is the Ravager's whole game.
func _slam() -> void:
	AudioBus.play_synth_at("impact_metal", global_position, -1.0, 0.6)
	if _eye_light:
		_eye_light.light_energy = 5.0
	if target and is_instance_valid(target):
		if global_position.distance_to(target.global_position) <= slam_radius:
			var d = target.get_node_or_null("Damageable")
			if d:
				d.apply_damage(slam_damage, self)

func _process(_delta: float) -> void:
	if state == State.DEAD:
		return
	if _eye_light:
		var tell := 3.5 if _windup > 0.0 else 0.0
		_eye_light.light_energy = lerpf(_eye_light.light_energy, 1.7 + recoil * 2.0 + tell, 0.2)

func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= attack_range * 1.3:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(slam_damage * 0.6, self)  # a swipe between leaps
		recoil = 1.0
		AudioBus.play_synth_at("impact_metal", global_position, -5.0, 1.1)
