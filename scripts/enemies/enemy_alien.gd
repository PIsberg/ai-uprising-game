class_name EnemyAlien
extends EnemyBase
## An organic flying alien — the machines' new off-world allies. It hovers in,
## swoops at the player and HEADBUTTS in melee, then peels off to circle and
## dive again (it does not kamikaze). Visuals are an imported animated creature
## (RobotModel on $Model drives its Flying_Idle / Fast_Flying / Headbutt clips).

@export var intercept_height: float = 1.4 ## Flies toward the player's chest height.
@export var headbutt_range: float = 2.2
@export var headbutt_damage: float = 22.0
@export var swoop_speed: float = 11.0

var _butt_cd: float = 0.0
var _peel: float = 0.0 ## While >0, peeling off after a strike (don't re-approach).

func _ready() -> void:
	max_health = 70.0
	move_speed = 8.5
	turn_speed = 9.0
	sight_range = 42.0
	sight_angle_deg = 260.0
	attack_range = 28.0
	preferred_range = 0.5
	attack_cooldown = 1.2
	score_value = 150
	stagger_threshold = 60.0
	super._ready()

func _apply_gravity(_delta: float) -> void:
	pass # it flies

func _state_chase(delta: float) -> void:
	if target == null:
		set_state(State.IDLE)
		return
	_move_toward(target.global_position, delta)

func _state_attack(delta: float) -> void:
	_state_chase(delta)

func _move_toward(dest: Vector3, delta: float) -> void:
	var ty: float = (target.global_position.y if target else dest.y) + intercept_height
	# Peeling off: rise and back away after a hit so the dive reads as a cycle.
	if _peel > 0.0 and target:
		ty = target.global_position.y + intercept_height + 1.6
	var to := Vector3(dest.x, ty, dest.z) - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var spd := chase_speed() * (1.3 if _peel <= 0.0 else 0.7)
	if flat.length() > 0.05:
		var d := flat.normalized()
		if _peel > 0.0:
			d = -d # back off
		velocity.x = move_toward(velocity.x, d.x * spd, 16.0 * delta)
		velocity.z = move_toward(velocity.z, d.z * spd, 16.0 * delta)
		if _peel <= 0.0:
			_face_dir(d, delta)
	velocity.y = move_toward(velocity.y, (ty - global_position.y) * 5.0, 30.0 * delta)

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_butt_cd = maxf(0.0, _butt_cd - delta)
	_peel = maxf(0.0, _peel - delta)
	super._physics_process(delta)
	if target and _butt_cd <= 0.0 and _peel <= 0.0 \
			and global_position.distance_to(target.global_position) <= headbutt_range:
		_headbutt()

func _headbutt() -> void:
	if target == null:
		return
	var d = target.get_node_or_null("Damageable")
	if d:
		d.apply_damage(headbutt_damage, self)
	recoil = 1.0   # plays the Headbutt clip via RobotModel
	_butt_cd = 1.4
	_peel = 0.7
	# Lunge through the target, then peel off up and back.
	var away := (global_position - target.global_position)
	away.y = 0.0
	if away.length() > 0.1:
		velocity = away.normalized() * swoop_speed + Vector3.UP * 4.5
	if target is CharacterBody3D:
		var push := (target.global_position - global_position)
		push.y = 0.0
		(target as CharacterBody3D).velocity += push.normalized() * 5.0 + Vector3.UP * 1.5
	if has_node("/root/AudioBus"):
		AudioBus.play_synth_at("impact_metal", global_position, 0.0, 0.8)
