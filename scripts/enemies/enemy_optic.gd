class_name EnemyOptic
extends EnemyAndroid
## OPTICON — a repurposed maintenance unit: a boxy yellow body slung under a single
## glaring red optic, scuttling on spindly tool-legs. It was built to weld and
## repair; now it lances you with its cutting beam. Slow and fragile, but its shots
## sting and it never blinks.

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

var _beam: ElectricBeam = null
var _beam_windup: float = 0.0
var _beam_time: float = 0.0
var _beam_cd: float = 0.0
var _beam_dir: Vector3 = Vector3.FORWARD
var _beam_tick_t: float = 0.0
var _beam_charge: float = 0.0   ## 0..1, unused for visuals here (eye_glow is off on this model)

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
		_beam = ElectricBeam.new()
		_beam.set_color(BEAM_COLOR)
		get_tree().current_scene.add_child(_beam)
	AudioBus.play_synth_at("plasma_fire", _beam_origin(), -3.0, 0.9)

func _beam_origin() -> Vector3:
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
	if _beam_time <= 0.0:
		_end_beam()

func _end_beam() -> void:
	_beam_windup = 0.0
	_beam_time = 0.0
	_beam_charge = 0.0
	_beam_cd = BEAM_COOLDOWN
	if _beam:
		_beam.deactivate()

func _on_died(source: Node) -> void:
	# Never let a beam linger mid-fire once this unit dies.
	_beam_windup = 0.0
	_beam_time = 0.0
	_beam_charge = 0.0
	if is_instance_valid(_beam):
		_beam.queue_free()
		_beam = null
	super._on_died(source)
