class_name EnemyMauler
extends EnemyBase
## Heavy melee brawler: closes in and slams with both fists. Slow but very tough.
## Visuals from a real robot model in mauler.tscn (RobotModel plays its Punch
## clip on each attack).
##
## Signature move: OVERLOAD. Critically damaged it stops fighting fair — the
## core glows red-hot, it charges you at speed, and a few seconds later it
## DETONATES (kamikaze). Kill it before it closes, or run.

@export var slam_damage: float = 34.0
@export var overload_at: float = 0.35 ## health fraction that trips the overload
@export var overload_fuse: float = 3.0
@export var overload_damage: float = 42.0
@export var overload_radius: float = 4.5

var _overloading: bool = false
var _fuse_t: float = 0.0
var _glow_light: OmniLight3D


func _ready() -> void:
	max_health = 210.0
	move_speed = 5.0
	turn_speed = 5.5
	sight_range = 32.0
	sight_angle_deg = 180.0
	attack_range = 3.6
	preferred_range = 1.8
	attack_cooldown = 1.5
	attack_lunge_speed = 9.0
	score_value = 175
	stagger_threshold = 130.0
	super._ready()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state == State.DEAD:
		return
	if not _overloading and hp and hp.current_health / hp.max_health <= overload_at:
		_begin_overload()
	if _overloading:
		_fuse_t -= delta
		# Rising red pulse + accelerating beeps sell the countdown.
		if _glow_light:
			_glow_light.light_energy = 3.0 + 4.0 * absf(sin((overload_fuse - _fuse_t) * (6.0 + (overload_fuse - _fuse_t) * 4.0)))
		var close := target != null and is_instance_valid(target) \
			and global_position.distance_to(target.global_position) <= 2.4
		if _fuse_t <= 0.0 or close:
			_detonate()

func _begin_overload() -> void:
	_overloading = true
	_fuse_t = overload_fuse
	_speed_mult *= 1.7 # a wounded mauler RUNS
	_glow_light = OmniLight3D.new()
	_glow_light.light_color = Color(1.0, 0.2, 0.1)
	_glow_light.omni_range = 6.0
	add_child(_glow_light)
	_glow_light.position = Vector3(0, 1.2, 0)
	AudioBus.play_synth_at("overlord_glitch", global_position, -2.0, 0.7)

func _detonate() -> void:
	if state == State.DEAD:
		return
	AudioBus.play_synth_at("explosion", global_position, 0.0, 0.9)
	if target and is_instance_valid(target) \
			and global_position.distance_to(target.global_position) <= overload_radius:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(overload_damage, self)
		if target.has_method("shake"):
			target.shake(0.6)
	hp.apply_damage(hp.max_health * 10.0, self) # takes itself out in the blast

func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= attack_range * 1.4:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(slam_damage, self)
		AudioBus.play_synth_at("impact_metal", global_position, -4.0, 1.2)
	_attack_lunge()
