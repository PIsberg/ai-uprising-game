class_name EnemyServer
extends EnemyBase
## MAITRE-D' — a cafe serving robot turned sinister. Trundles in on its wheeled
## base, then swings its serving trays like cleavers, bashing the player back.
## Slow but tanky and heavy-hitting. Built model:
## assets/models/robots/serving_bot.glb (tools/blender/build_server.py; RobotModel
## leans it; no walk rig).
##
## Signature move: CLEAVER SERVICE — outside tray reach it hurls spinning
## serving-cleavers, so closing on it (or fleeing it) is never free.
##
## Rig. The build script exports the head (with its face) and the two thin
## arms gripping the top tray as their own meshes, the column of trays as the
## rest. `_setup_rig` takes them by name once RobotModel has placed the model;
## the neck, shoulders and hands are measured constants. `_tick_rig` then:
## turns the head onto you whenever it is engaged, and keeps it on you right
## through a pirouette (the body spins, the face does not leave you); throws
## each cleaver with the right arm, cocked up and back over the shoulder for a
## beat (the tell) and whipped forward, the cleaver leaving the hand at the end
## of the whip; and flings both arms out through the tray-bash's pirouette
## (`_whirl`, 0.35 s), the trays and arms whirling round like blades. The
## throw used to be a pirouette too. tests/server_rig_probe.

@export var bash_damage: float = 26.0
@export var cleaver_damage: float = 16.0
@export var cleaver_speed: float = 17.0
@export var cleaver_cooldown: float = 2.4

var _cleaver_cd: float = 0.0

const WHIRL_TIME := 0.35 ## s for the full-turn pirouette
var _whirl_t := -1.0     ## s into the current whirl, < 0 when still

# Rig (body frame, the model at its import size; x mirrored per side, left = -x).
const NECK := Vector3(0.0, 1.5, 0.0)
const SHOULDER := Vector3(0.42, 1.266, -0.045)   ## the arm's root at the column
const HAND := Vector3(0.42, 1.094, -0.515)       ## its tip on the top tray's rim
const HEAD_YAW_MAX := 1.5    ## rad either side while standing (free through a whirl)
const HEAD_PITCH_MAX := 0.45
const HEAD_RATE := 9.0       ## rad/s the head turns
const COCK := 2.4            ## rad the throwing arm swings up and back over the shoulder
const WHIP_END := 0.3        ## rad short of hanging where the cleaver leaves
const WIND_T := 0.22         ## s of cock (the tell)
const WHIP_T := 0.12         ## s of whip
const RECOVER_T := 0.3       ## s the arm settles after the release
const FLING_YAW := 1.3       ## rad each arm swings outward in the bash
const FLING_PITCH := 0.5     ## rad they lift with it
var _rig_ready := false
var _head_e: Array = []
var _arm_e: Array = [[], []]            ## left, right
var _arm_mi: Array = [null, null]
var _hand_local: Array = [Vector3.ZERO, Vector3.ZERO]
var _head_yaw := 0.0
var _head_pitch := 0.0
var _throw_t := -1.0                    ## s into the throw, < 0 when not throwing
var _thrown := false                    ## this throw's cleaver has left the hand
var _arm_pitch := 0.0                   ## right arm, rad about the shoulder
var _fling := 0.0                       ## 0..1 both arms flung out

func _ready() -> void:
	max_health = 155.0
	move_speed = 3.3
	turn_speed = 4.2
	sight_range = 30.0
	sight_angle_deg = 180.0
	attack_range = 3.4
	preferred_range = 1.8
	attack_cooldown = 1.8
	attack_lunge_speed = 6.0
	telegraph_time = 0.45
	score_value = 150
	stagger_threshold = 52.0
	super._ready()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state == State.DEAD:
		return
	_tick_whirl(delta)
	_tick_rig(delta)
	_cleaver_cd = maxf(0.0, _cleaver_cd - delta)
	if target and is_instance_valid(target) and _cleaver_cd <= 0.0 and _throw_t < 0.0 \
			and state in [State.CHASE, State.ATTACK] and _can_see(target):
		var dist := global_position.distance_to(target.global_position)
		if dist > attack_range * 1.2 and dist < 16.0:
			_cleaver_cd = cleaver_cooldown
			_begin_throw()

func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	_whirl()
	if global_position.distance_to(target.global_position) <= attack_range * 1.4:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(bash_damage, self)
		if target.has_method("shake"):
			target.shake(0.45)
		# A heavy tray-swing knocks the player back off their feet.
		if "velocity" in target and target is Node3D:
			var away: Vector3 = (target as Node3D).global_position - global_position
			away.y = 0.0
			if away.length() > 0.1:
				target.velocity += away.normalized() * 7.5 + Vector3.UP * 2.5
		AudioBus.play_synth_at("impact_metal", global_position, -3.0, 0.8)
	_attack_lunge()

## Start a pirouette: one full turn of the model, eased out, over WHIRL_TIME.
func _whirl() -> void:
	_whirl_t = 0.0
	AudioBus.play_synth_at("rotor_whir", global_position, -6.0, 1.4)

func _tick_whirl(delta: float) -> void:
	if _whirl_t < 0.0:
		return
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		_whirl_t = -1.0
		return
	_whirl_t += delta
	var f := clampf(_whirl_t / WHIRL_TIME, 0.0, 1.0)
	model.rotation.y = TAU * (1.0 - pow(1.0 - f, 2.0))
	if f >= 1.0:
		model.rotation.y = 0.0
		_whirl_t = -1.0

## Cock the right arm: the cleaver leaves the hand at the end of the whip.
func _begin_throw() -> void:
	_throw_t = 0.0
	_thrown = false

## Where the cleaver leaves: the right hand once the rig is up, else a point
## over the column.
func _throw_origin() -> Vector3:
	if _rig_ready and _arm_mi[1] != null:
		return (_arm_mi[1] as MeshInstance3D).global_transform * (_hand_local[1] as Vector3)
	return global_position + Vector3.UP * 1.4

func _release_cleaver() -> void:
	if target == null or not is_instance_valid(target):
		return
	recoil = 0.8
	var from := _throw_origin()
	ThrownCleaver.throw_at(get_tree().current_scene, from,
		target.global_position + Vector3.UP * 0.8, cleaver_speed, cleaver_damage)
	AudioBus.play_synth_at("impact_metal", from, -9.0, 2.4)

## Find the parts once RobotModel has placed the model (it hides the mesh until
## then on fitted models; this one imports at size).
func _setup_rig() -> void:
	var model := get_node_or_null("Model")
	var head := model.find_child("Head", true, false) as MeshInstance3D if model else null
	if head == null or not head.is_visible_in_tree():
		return
	_rig_ready = true # one attempt: a model without the parts keeps still
	var arms: Array = [model.find_child("ArmL", true, false) as MeshInstance3D, model.find_child("ArmR", true, false) as MeshInstance3D]
	if arms[0] == null or arms[1] == null:
		return
	var frame := rig_frame()
	_head_e = PartRig.entry(self, head)
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		_arm_e[side] = PartRig.entry(self, arms[side])
		_arm_mi[side] = arms[side]
		_hand_local[side] = (arms[side] as MeshInstance3D).global_transform.affine_inverse() * (frame * Vector3(HAND.x * sx, HAND.y, HAND.z))

func _engaged() -> bool:
	return target != null and is_instance_valid(target) and state in [State.ALERT, State.CHASE, State.ATTACK]

## Turn the head, throw, fling (see the class doc).
func _tick_rig(delta: float) -> void:
	if not _rig_ready:
		_setup_rig()
		return
	if _head_e.is_empty() or _arm_mi[0] == null:
		return
	# Head: onto the target in the body frame, else forward. A whirl spins the
	# Model node under the head, and the rig frame leaves that spin out (it is
	# not a nudge), so through a whirl the head's turn is the target's yaw less
	# the spin: the face stays on you while the body goes round.
	var want_yaw := 0.0
	var want_pitch := 0.0
	if _engaged():
		var to: Vector3 = rig_frame().affine_inverse() * ((target as Node3D).global_position + Vector3.UP * RobotModel.aim_height(target)) - NECK
		want_yaw = atan2(-to.x, -to.z)
		want_pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -HEAD_PITCH_MAX, HEAD_PITCH_MAX)
		if _whirl_t < 0.0:
			want_yaw = clampf(want_yaw, -HEAD_YAW_MAX, HEAD_YAW_MAX)
	if _whirl_t >= 0.0:
		var model := get_node_or_null("Model") as Node3D
		_head_yaw = wrapf(want_yaw - (model.rotation.y if model else 0.0), -PI, PI)
	else:
		_head_yaw = move_toward(_head_yaw, want_yaw, HEAD_RATE * delta)
	_head_pitch = move_toward(_head_pitch, want_pitch, HEAD_RATE * delta)
	PartRig.pose(_head_e, PartRig.turn(NECK, Vector3.UP, _head_yaw) * PartRig.turn(NECK, Vector3.RIGHT, _head_pitch))
	# Throw: cock, whip, release, recover.
	if _throw_t >= 0.0:
		_throw_t += delta
		if _throw_t < WIND_T:
			_arm_pitch = COCK * smoothstep(0.0, 1.0, _throw_t / WIND_T)
		elif _throw_t < WIND_T + WHIP_T:
			_arm_pitch = lerpf(COCK, WHIP_END, (_throw_t - WIND_T) / WHIP_T)
		else:
			if not _thrown:
				_thrown = true
				_arm_pitch = WHIP_END
				_release_cleaver()
			_arm_pitch = lerpf(WHIP_END, 0.0, clampf((_throw_t - WIND_T - WHIP_T) / RECOVER_T, 0.0, 1.0))
			if _throw_t >= WIND_T + WHIP_T + RECOVER_T:
				_arm_pitch = 0.0
				_throw_t = -1.0
	# Bash: both arms flung out through the pirouette.
	var want_fling := 1.0 if _whirl_t >= 0.0 else 0.0
	_fling = move_toward(_fling, want_fling, delta / (0.12 if want_fling > 0.0 else 0.25))
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var shoulder := Vector3(SHOULDER.x * sx, SHOULDER.y, SHOULDER.z)
		var f := smoothstep(0.0, 1.0, _fling)
		var lay := PartRig.turn(shoulder, Vector3.UP, -sx * FLING_YAW * f) * PartRig.turn(shoulder, Vector3.RIGHT, FLING_PITCH * f + (_arm_pitch if side == 1 else 0.0))
		PartRig.pose(_arm_e[side], lay)
