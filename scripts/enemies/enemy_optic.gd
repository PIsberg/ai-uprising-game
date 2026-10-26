class_name EnemyOptic
extends EnemyAndroid
## OPTICON — a repurposed maintenance unit: a boxy camera head with one glaring
## lens over a small pelvis, two jointed legs ending in wheel feet, and a
## welding torch hung off each knee. It was built to roll about and weld; now
## it rolls up and lances you with its torches. Slow and fragile, but its shots
## sting and it never blinks.
##
## Rig. utility_robot.glb is cut offline (tools/blender/split_regions.py with
## tools/blender/cfg_utility_robot_parts.json) into the two wheel feet, the two
## torches (each with its knee hinge) and the rest (`Body`: head, pelvis,
## thighs, shins). `_setup_rig` takes each axle from its wheel's bounds and the
## torches' hinges and tips from measured constants, once RobotModel's fit has
## landed. `_tick_rig` then rolls the wheels by ground speed about their axles
## and swings the torches: hanging forward-down at rest, raised together onto
## you through the cutting beam's charge and sweep (`AimedPart`, the ENFORCER's
## rifle aim), falling back when the beam ends. The beam leaves the right
## torch's tip and a second beam the left's. tests/optic_rig_probe.

# --- Cutting Beam: a scaled-down version of the terminator boss's Optic Lance.
# It's a minion, not a boss, so the tell is the same (a visible charge) but the
# beam itself is short, its sweep is slow, and it's on a long cooldown — you can
# always outrun or outlast it. Its android burst rifle is still the filler attack
# up close / off cooldown.
const BEAM_RANGE := 26.0        ## matches attack_range
const BEAM_WINDUP := 0.7        ## clear charge tell before it fires
const BEAM_DURATION := 1.0      ## short — a minion sting, not a sustained boss beam
const BEAM_TURN := 1.1          ## rad/s sweep — slow enough to strafe out of
const BEAM_COLOR := Color(1.0, 0.25, 0.15)
const BEAM_COOLDOWN := 4.0
const BEAM_TICK := 0.15         ## damage cadence while it's on you
const BEAM_DPS := 7.0           ## full DPS only if you stand still in a slow, dodgeable sweep

var _beam: ElectricBeam = null  ## from the right torch: the one that is traced and hurts
var _beam2: ElectricBeam = null ## from the left torch to the same point: looks only
var _beam_windup: float = 0.0
var _beam_time: float = 0.0
var _beam_cd: float = 0.0
var _beam_dir: Vector3 = Vector3.FORWARD
var _beam_tick_t: float = 0.0
var _beam_charge: float = 0.0   ## 0..1, unused for visuals here (eye_glow is off on this model)

# Rig (body frame at fit_height 1.7, measured headless on the cut model; x
# mirrored per side, left = -x). The hinge is the barrel the torch hangs from
# at the knee, the tip the welding point.
const TORCH_HINGE := Vector3(0.545, 0.785, -0.29)
const TORCH_TIP := Vector3(0.775, 0.268, -0.944)
const TORCH_RATE := 4.0         ## 1/s onto the aim: raised in a quarter second, same back
const TORCH_HOLD := 6.0         ## m ahead of the tip the torch follows the sweeping beam
var _rig_ready := false
var _torch: Array = [null, null]        ## AimedPart per side (0 = left)
var _torch_mi: Array = [null, null]     ## the torch meshes
var _tip_local: Array = [Vector3.ZERO, Vector3.ZERO] ## tip in each torch's own frame
var _torch_tip: Array = [Vector3.ZERO, Vector3.ZERO] ## world, after this tick's pose
var _wheel_e: Array = [[], []]
var _axle: Array = [Vector3.ZERO, Vector3.ZERO]
var _wheel_r := 0.12
var _wheel_spin := 0.0

func _ready() -> void:
	super._ready()
	max_health = 95.0
	move_speed = 3.4
	turn_speed = 6.5
	attack_range = 26.0
	preferred_range = 14.0
	hitscan_damage = 14.0
	burst_count = 2
	score_value = 170
	hp.max_health = max_health
	hp.current_health = max_health

func _physics_process(delta: float) -> void:
	_beam_cd = maxf(0.0, _beam_cd - delta)
	if state != State.DEAD:
		_tick_rig(delta)
	# The beam owns the unit while it's charging/firing — planted, no bolts.
	if _beaming():
		_process_beam(delta)
		return
	super._physics_process(delta)

func _state_attack(delta: float) -> void:
	if target == null or not _can_see(target):
		set_state(State.CHASE)
		return
	_face_target(delta)
	# Opening-seconds grace: plant and track, don't start anything new.
	if GameState.attack_grace_active():
		_decelerate()
		return
	var dist := global_position.distance_to(target.global_position)
	# Beam when it's off cooldown and you're at a lance-able distance; otherwise
	# fall back to the android's dodge/flank burst-rifle behaviour.
	if _beam_cd <= 0.0 and dist >= 4.0 and dist <= BEAM_RANGE and _can_see(target):
		_begin_beam()
		return
	super._state_attack(delta)

func _beaming() -> bool:
	return _beam_windup > 0.0 or _beam_time > 0.0

## Fire up the cutting beam: a brief charge, then a sweeping red laser.
func _begin_beam() -> void:
	_beam_windup = BEAM_WINDUP
	_beam_time = 0.0
	_beam_tick_t = 0.0
	if target:
		_beam_dir = (target.global_position + Vector3.UP * 0.7 - _beam_origin()).normalized()
	if _beam == null:
		_beam = _make_beam()
	if _beam2 == null and _rigged():
		_beam2 = _make_beam()
	AudioBus.play_synth_at("plasma_fire", _beam_origin(), -3.0, 0.9)

func _make_beam() -> ElectricBeam:
	var b := ElectricBeam.new()
	b.set_color(BEAM_COLOR)
	get_tree().current_scene.add_child(b)
	return b

func _rigged() -> bool:
	return _rig_ready and _torch[1] != null

## Where the beam leaves: the right torch's welding tip once the rig is up,
## else the scene's Muzzle at the lens.
func _beam_origin() -> Vector3:
	if _rigged():
		return _torch_tip[1]
	return muzzle.global_position if muzzle else global_position + Vector3.UP * 0.8

## Drive the charge + the tracking, damaging beam.
func _process_beam(delta: float) -> void:
	# Plant and keep turning to face the player so the sweep starts aimed.
	_decelerate()
	if not is_on_floor():
		_apply_gravity(delta)
	move_and_slide()
	if target and _can_see(target):
		_face_target(delta)

	var origin := _beam_origin()
	var aim_pt := (target.global_position + Vector3.UP * 0.7) if target else origin + _beam_dir
	var desired := (aim_pt - origin).normalized()

	# Charge phase: locked onto the player, not yet lethal.
	if _beam_windup > 0.0:
		_beam_windup -= delta
		_beam_charge = clampf(1.0 - _beam_windup / BEAM_WINDUP, 0.0, 1.0)
		_beam_dir = desired # lock straight onto the player at ignition
		if _beam_windup <= 0.0:
			_beam_time = BEAM_DURATION
			AudioBus.play_synth_at("plasma_fire", origin, -1.0, 0.75)
		return

	# Firing: sweep toward the player at a capped, dodgeable rate.
	_beam_charge = 1.0
	_beam_time -= delta
	var max_step := BEAM_TURN * delta
	var ang := _beam_dir.angle_to(desired)
	if ang > 0.0001:
		_beam_dir = _beam_dir.slerp(desired, clampf(max_step / ang, 0.0, 1.0))

	# Trace the beam: world + player. Damage only when it actually lands on you.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + _beam_dir * BEAM_RANGE)
	q.collision_mask = 0b0000011
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var end_point := origin + _beam_dir * BEAM_RANGE
	var on_player := false
	if not hit.is_empty():
		end_point = hit.position
		var col: Node = hit.collider
		on_player = col != null and col.is_in_group("player")
		_beam_tick_t -= delta
		if on_player and _beam_tick_t <= 0.0:
			var d: Node = col.get_node_or_null("Damageable")
			if d:
				d.apply_damage(BEAM_DPS * BEAM_TICK, self)
			_beam_tick_t = BEAM_TICK
	if _beam:
		_beam.update_beam(origin, end_point, true)
	if _beam2:
		_beam2.update_beam(_torch_tip[0], end_point, true)
	if _beam_time <= 0.0:
		_end_beam()

func _end_beam() -> void:
	_beam_windup = 0.0
	_beam_time = 0.0
	_beam_charge = 0.0
	_beam_cd = BEAM_COOLDOWN
	if _beam:
		_beam.deactivate()
	if _beam2:
		_beam2.deactivate()

## Find the parts once the fit has landed (RobotModel hides the mesh until
## then): each axle is its wheel's centre; the torches hang from the measured
## hinges with their tips at the measured welding points.
func _setup_rig() -> void:
	var model := get_node_or_null("Model")
	var probe := model.find_child("TorchL", true, false) as MeshInstance3D if model else null
	if probe == null or not probe.is_visible_in_tree():
		return
	_rig_ready = true # one attempt: a model without the parts keeps still
	var names := [["TorchL", "WheelL"], ["TorchR", "WheelR"]]
	var frame := rig_frame()
	for side in 2:
		var torch := model.find_child(names[side][0], true, false) as MeshInstance3D
		var wheel := model.find_child(names[side][1], true, false) as MeshInstance3D
		if torch == null or wheel == null:
			_torch = [null, null]
			return
		var sx := -1.0 if side == 0 else 1.0
		var hinge := Vector3(TORCH_HINGE.x * sx, TORCH_HINGE.y, TORCH_HINGE.z)
		var tip := Vector3(TORCH_TIP.x * sx, TORCH_TIP.y, TORCH_TIP.z)
		_torch[side] = AimedPart.new([PartRig.entry(self, torch)], hinge, tip, TORCH_RATE)
		_torch_mi[side] = torch
		_tip_local[side] = torch.global_transform.affine_inverse() * (frame * tip)
		_torch_tip[side] = frame * tip
		var wb: AABB = frame.affine_inverse() * (wheel.global_transform * wheel.mesh.get_aabb())
		_axle[side] = wb.get_center()
		_wheel_r = wb.size.y * 0.5
		_wheel_e[side] = PartRig.entry(self, wheel)

## Roll the wheels and swing the torches (see the class doc).
func _tick_rig(delta: float) -> void:
	if not _rig_ready:
		_setup_rig()
		return
	if _torch[0] == null:
		return
	# Wheels: fixed axles, so they roll by the ground covered, forward or back
	# (a sidestep still turns them: the feet are not casters).
	var ground := Vector2(velocity.x, velocity.z).length()
	var fwd := velocity.dot(-global_transform.basis.z)
	_wheel_spin = fposmod(_wheel_spin + (ground if fwd >= 0.0 else -ground) / _wheel_r * delta, TAU)
	for side in 2:
		# Rolling forward (-Z) the top of a wheel moves forward: a negative turn about +X.
		PartRig.pose(_wheel_e[side], PartRig.turn(_axle[side], Vector3.RIGHT, -_wheel_spin))
	# Torches: raised onto you through the beam's charge, following the sweep
	# while it burns, hanging otherwise.
	var engaged := _beaming()
	var aim: Variant = null
	if engaged:
		if _beam_time > 0.0:
			aim = _torch_tip[1] + _beam_dir * TORCH_HOLD
		elif target and is_instance_valid(target):
			aim = (target as Node3D).global_position + Vector3.UP * 0.7
	for side in 2:
		_torch[side].tick(self, aim, engaged, delta)
		_torch_tip[side] = (_torch_mi[side] as MeshInstance3D).global_transform * (_tip_local[side] as Vector3)

func _on_died(source: Node) -> void:
	# Never let a beam linger mid-fire once this unit dies.
	_beam_windup = 0.0
	_beam_time = 0.0
	_beam_charge = 0.0
	for b in [_beam, _beam2]:
		if is_instance_valid(b):
			b.queue_free()
	_beam = null
	_beam2 = null
	super._on_died(source)
