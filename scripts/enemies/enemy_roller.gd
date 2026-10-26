class_name EnemyRoller
extends EnemyDog
## ROLLER — a monowheel brawler: a gold drum balanced on a single fat wheel, with
## whipping spring-arms. It rolls in fast and rams, knocking you back. Tougher than
## the K-9 hound but a touch slower to turn, so circle-strafe it.
##
## Signature move: the RAM. A monowheel leaping into the air like the hound would
## look wrong, so this fully replaces EnemyDog's airborne pounce with a grounded
## charge: a brief plant/spin-up tell, then a fast straight-line drive at the
## player that ends on impact (not on landing — it never leaves the floor) with
## a bite plus a shove that knocks the player back.
##
## Rig. wheeled_robot.glb is cut offline (tools/blender/split_regions.py with
## tools/blender/cfg_wheeled_robot_parts.json) into the WHEEL (the tire and
## spokes between the fork legs), the two coiled spring ARMS (everything
## outboard of the drum between the claws and the shoulder housings) and the
## rest (`Body`: drum, fork, head). It is cut offline rather than by
## PartRig.split_groups at spawn because, in a windowed run, reading this
## mesh's vertices back from the renderer returns about 400 garbage positions
## (headless it is clean; the HOWITZER's and DOG's meshes read clean in both),
## which covered the screen in spikes. `_setup_rig` takes each part's joint
## from its bounds (no vertex read), once RobotModel's fit has landed.
## `_tick_rig` then rolls the wheel by ground speed about its axle, spins it
## up on the spot through the ram's plant (the tell), rears the drum back over
## the wheel in the plant and tips it into the charge, and whips the arms:
## cocked back and out through the plant, lashed forward together for the
## charge, flexing with the roll in between.

const RAM_SPEED := 18.0        ## faster than move_speed — this is the charge, not the chase
const RAM_WINDUP := 0.35       ## plant/spin-up tell before it commits
const RAM_MAX_TIME := 0.55     ## charge times out even if it never lands a hit
const RAM_IMPACT_RANGE := 2.4  ## charge ends early once it's this close
const RAM_KNOCK := 11.0        ## horizontal shove applied to the player on impact

var _ramming: bool = false
var _ram_t: float = 0.0
var _ram_windup_t: float = 0.0
var _ram_cd: float = 0.0

const SHOULDER_IN := 0.05                ## m below the arm's top and behind its rearmost, body frame
const ARM_COCK := 0.8                    ## rad the arms sweep back and out in the plant
const ARM_LASH := -0.9                   ## rad they sweep forward together in the charge
const ARM_FLEX := 0.12                   ## rad they flex with the roll
const REAR := 0.22                       ## rad the drum rears back about the axle in the plant
const TIP := -0.18                       ## rad it tips into the charge
const SPINUP := 30.0                     ## rad/s the wheel spins on the spot in the plant

var _rig_ready := false
var _body_e: Array = []
var _wheel_e: Array = []
var _arm_e: Array = [[], []]             ## left, right
var _arm_pivot: Array = [Vector3.ZERO, Vector3.ZERO]
var _axle := Vector3.ZERO                ## wheel centre, body frame
var _wheel_r := 0.3
var _wheel_spin := 0.0
var _arm_sweep := 0.0
var _tilt := 0.0

func _ready() -> void:
	super._ready()
	bite_damage = 24.0
	max_health = 175.0    # a heavy steel drum — soaks more than a hound
	move_speed = 8.0
	turn_speed = 7.5
	attack_range = 3.4
	score_value = 175
	stagger_threshold = 46.0
	hp.max_health = max_health
	hp.current_health = max_health

## Plant → charge → impact, all on the ground. This can't fall through to
## EnemyDog's _physics_process (that's the airborne pounce we're replacing), so
## the base ground-AI tick it would otherwise reach via `super` is replicated
## here instead.
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_tick_rig(delta)
	if _emp_t > 0.0:
		_emp_t = maxf(0.0, _emp_t - delta)
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		_apply_gravity(delta)
		move_and_slide()
		return
	_ram_cd = maxf(0.0, _ram_cd - delta)
	if _ramming:
		# Gravity holds it down — no launch, no hop, just a fast roll.
		_apply_gravity(delta)
		move_and_slide()
		_ram_t += delta
		var close := target != null and is_instance_valid(target) \
			and global_position.distance_to(target.global_position) <= RAM_IMPACT_RANGE
		if close or _ram_t > RAM_MAX_TIME:
			_ramming = false
			_ram_cd = pounce_cooldown
			_ram_impact()
		return
	if _ram_windup_t > 0.0:
		_ram_windup_t -= delta
		_decelerate()
		_face_target(delta)
		_apply_gravity(delta)
		move_and_slide()
		if _ram_windup_t <= 0.0:
			_launch_ram()
		return
	# Base ground AI (replicated from EnemyBase._physics_process — see comment above).
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_state_timer += delta
	recoil = move_toward(recoil, 0.0, delta * 9.0)
	_perceive()
	_run_state(delta)
	_apply_gravity(delta)
	move_and_slide()
	_update_hit_react(delta)
	_update_overload(delta)
	_oil_cd = maxf(0.0, _oil_cd - delta)
	_poise = maxf(0.0, _poise - delta * 26.0)
	_update_locomotion_audio(delta)
	if target and _ram_cd <= 0.0 and is_on_floor() \
			and state in [State.CHASE, State.ATTACK]:
		var dist := global_position.distance_to(target.global_position)
		# Reuse the hound's pounce band — same "mid range, has to commit" fairness.
		if dist >= pounce_min and dist <= pounce_max and _can_see(target):
			_ram_windup_t = RAM_WINDUP
			recoil = 0.6
			AudioBus.play_synth_at("overlord_glitch", global_position, -8.0, 1.9)

func _launch_ram() -> void:
	if target == null or not is_instance_valid(target):
		return
	_ramming = true
	_ram_t = 0.0
	var dir := target.global_position - global_position
	dir.y = 0.0
	dir = dir.normalized()
	velocity.x = dir.x * RAM_SPEED
	velocity.z = dir.z * RAM_SPEED
	recoil = 1.0
	AudioBus.play_synth_at("impact_metal", global_position, -7.0, 2.2)

## Bite + shove on landing a ram — the knockback is what sells "rammed", not just bitten.
func _ram_impact() -> void:
	for player in GameState.players():
		if player and player is Node3D \
				and global_position.distance_to((player as Node3D).global_position) <= RAM_IMPACT_RANGE + 0.2:
			var d = player.get_node_or_null("Damageable")
			if d:
				d.apply_damage(bite_damage, self)
			var away: Vector3 = (player as Node3D).global_position - global_position
			away.y = 0.0
			away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
			if player is CharacterBody3D and "velocity" in player:
				(player as CharacterBody3D).velocity += away * RAM_KNOCK + Vector3.UP * 2.5
	AudioBus.play_synth_at("impact_metal", global_position, -5.0, 1.6)

## A part's bounds in the body frame.
func _part_box(mi: MeshInstance3D) -> AABB:
	return rig_frame().affine_inverse() * (mi.global_transform * mi.mesh.get_aabb())

## Find the parts once the fit has landed (RobotModel hides the mesh until
## then): the axle is the wheel's centre, each shoulder sits just inside the
## arm's top rear corner on the drum's side.
func _setup_rig() -> void:
	var model := get_node_or_null("Model")
	var wheel := model.find_child("Wheel", true, false) as MeshInstance3D if model else null
	if wheel == null or not wheel.is_visible_in_tree():
		return
	_rig_ready = true # one attempt: a model without the parts keeps still
	var body := model.find_child("Body", true, false) as MeshInstance3D
	var arms: Array = [model.find_child("ArmL", true, false) as MeshInstance3D, model.find_child("ArmR", true, false) as MeshInstance3D]
	if body == null or arms[0] == null or arms[1] == null:
		return
	var wb := _part_box(wheel)
	_axle = wb.get_center()
	_wheel_r = wb.size.y * 0.5
	_body_e = PartRig.entry(self, body)
	_wheel_e = PartRig.entry(self, wheel)
	for side in 2:
		var box := _part_box(arms[side])
		var inner_x := box.end.x if side == 0 else box.position.x
		_arm_pivot[side] = Vector3(inner_x, box.end.y - SHOULDER_IN, box.end.z - SHOULDER_IN)
		_arm_e[side] = PartRig.entry(self, arms[side])

## Roll, rear, tip and whip (see the class doc).
func _tick_rig(delta: float) -> void:
	if not _rig_ready:
		_setup_rig()
		return
	if _wheel_e.is_empty():
		return
	var speed := velocity.dot(-global_transform.basis.z) # signed, along its facing
	var planting := _ram_windup_t > 0.0
	_wheel_spin = fposmod(_wheel_spin + (speed / _wheel_r + (SPINUP if planting else 0.0)) * delta, TAU)
	var want_tilt := REAR if planting else (TIP if _ramming else 0.0)
	_tilt = lerpf(_tilt, want_tilt, 1.0 - exp(-delta * 9.0))
	var want_sweep := ARM_COCK if planting else (ARM_LASH if _ramming else sin(_wheel_spin) * ARM_FLEX * clampf(absf(speed) / 4.0, 0.0, 1.0))
	_arm_sweep = lerpf(_arm_sweep, want_sweep, 1.0 - exp(-delta * (22.0 if _ramming else 9.0)))
	var tilt := PartRig.turn(_axle, Vector3.RIGHT, _tilt)
	PartRig.pose(_body_e, tilt)
	# Rolling forward (-Z) the top of the wheel moves forward: a negative turn about +X.
	PartRig.pose(_wheel_e, PartRig.turn(_axle, Vector3.RIGHT, -_wheel_spin))
	for side in 2:
		var sweep := PartRig.turn(_arm_pivot[side], Vector3.UP, _arm_sweep if side == 0 else -_arm_sweep)
		PartRig.pose(_arm_e[side], tilt * sweep)
