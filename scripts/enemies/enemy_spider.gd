class_name EnemySpider
extends EnemyBase
## Medium, fast, ground-hugging spider drone. Scuttles up to the player and bites
## in melee with a short lunge. Visuals are the imported "Trilobite" crawler
## (RobotModel on $Model drives the Run/Attack clips).

@export var bite_damage: float = 20.0
@export var lunge_speed: float = 13.5

@export_group("Leap")
@export var leap_windup: float = 0.45 ## Telegraph time before it springs (your window to shoot).
@export var leap_cooldown: float = 3.2
@export var leap_min: float = 4.0 ## Won't leap closer than this…
@export var leap_max: float = 16.0 ## …or further than this.
@export var leap_h_speed: float = 13.0
@export var leap_up: float = 7.5

var _leaping: bool = false
var _leap_time: float = 0.0
var _windup: float = 0.0
var _leap_cd: float = 0.0

# Spider scuttle: real spiders dart, freeze to "assess", then dart again, rather
# than gliding in a straight line. This cycles a short fast dash and a brief
# motionless pause while it's pursuing at range (it still commits up close).
var _scuttle_t: float = 0.0
var _assessing: bool = false


func _ready() -> void:
	super._ready()
	# A darting harasser: tougher than it looks (takes a few hits now) and fast
	# enough that the challenge is tracking it as it strafes and leaps, not
	# out-damaging it.
	max_health = 42.0
	move_speed = 11.0
	turn_speed = 14.0
	sight_range = 34.0
	sight_angle_deg = 300.0 # many eyes — near-omnidirectional awareness
	attack_range = 2.6
	preferred_range = 1.3
	attack_cooldown = 0.8
	score_value = 120
	hp.max_health = max_health
	hp.current_health = max_health

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
	# Scuttle cadence: while pursuing at range, dart for a beat then freeze to
	# assess. Skip it up close (let it press the bite) and when not engaged.
	if target and is_instance_valid(target) and is_on_floor() \
			and (state == State.CHASE or state == State.ALERT) \
			and global_position.distance_to(target.global_position) > attack_range * 1.5:
		_scuttle_t -= delta
		if _scuttle_t <= 0.0:
			_assessing = not _assessing
			_scuttle_t = randf_range(0.18, 0.34) if _assessing else randf_range(0.45, 0.8)
		if _assessing:
			_decelerate()
			_face_target(delta)
			_apply_gravity(delta)
			move_and_slide()
			# Still allow a leap to interrupt the freeze if the spacing is right.
			if _leap_cd <= 0.0:
				var ld := global_position.distance_to(target.global_position)
				if ld >= leap_min and ld <= leap_max and _can_see(target):
					_begin_windup()
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
	# Eye light flares bright during the windup — the tell to time your shot.
	var lamp := get_node_or_null("EyeLight") as OmniLight3D
	if lamp:
		var goal := 5.0 if _windup > 0.0 else 1.4
		lamp.light_energy = move_toward(lamp.light_energy, goal, delta * 30.0)


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
