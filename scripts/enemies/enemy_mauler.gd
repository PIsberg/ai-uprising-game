class_name EnemyMauler
extends EnemyBase
## Heavy melee brawler: closes in and slams with both fists. Slow but very tough.
## The slam is a GROUND POUND (_tick_pound): in reach it marks the floor where
## its target stands with a red ring, holds its ground for POUND_WINDUP, then
## brings both fists down on the mark. Whoever is still inside POUND_RADIUS
## takes slam_damage and is thrown outward; if nobody is, the fists stay
## buried for POUND_STUCK. It used to land the instant the cooldown ran out, on
## anything inside 5 m. tests/mauler_pound_probe.
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

const POUND_WINDUP := 0.75 ## s between the ring appearing and the fists landing
const POUND_RADIUS := 2.0 ## m around the mark: a walking player (5.5 m/s) clears it in 0.36 s
const POUND_STUCK := 0.9 ## s the fists stay buried after a pound that hit nobody
const RING_COLOR := Color(1.0, 0.22, 0.08)

enum Pound { NONE, WINDUP, STUCK }
var pound := Pound.NONE
var _pound_t: float = 0.0
var _pound_at := Vector3.ZERO ## the mark: fixed when the windup starts
var _ring: Node3D ## the floor telegraph, a child of the scene so it stays on the mark
var _ring_fill: MeshInstance3D

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
	hp.died.connect(_drop_ring.unbind(1))
	tree_exiting.connect(_drop_ring)


func _physics_process(delta: float) -> void:
	if state != State.DEAD and _tick_pound(delta):
		_tick_overload(delta)
		return
	super._physics_process(delta)
	if state == State.DEAD:
		return
	_tick_overload(delta)

func _tick_overload(delta: float) -> void:
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
	# a wounded mauler RUNS. Multiply the LIVE move_speed, not _speed_mult — the
	# latter is folded into move_speed once at spawn (_sync_stats) and never re-read,
	# so a runtime bump to it does nothing. The _overloading latch makes this one-shot.
	move_speed *= 1.7
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

## The base calls this in reach and off cooldown. It does not hit: it marks the
## floor under the target and starts the windup. An overloading MAULER does not
## pound at all (its charge ends in the blast).
func _perform_attack() -> void:
	if _overloading or pound != Pound.NONE or target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) > attack_range * 1.1:
		return
	pound = Pound.WINDUP
	_pound_t = POUND_WINDUP
	_pound_at = _floor_under(target.global_position)
	_spawn_ring()
	AudioBus.play_synth_at("mech_step", global_position, 2.0, 0.5) # a low growl as the fists go up
	# Rock back onto its heels: the coil before the fists come down.
	var back := global_position - _pound_at
	back.y = 0.0
	if back.length() > 0.05:
		velocity += back.normalized() * 2.0

## True when nothing else has the body: an EMP, a throw, a stagger, the reward
## hack, a courier run and the overload all cancel a pound.
func _pound_free() -> bool:
	return not _overloading and _emp_t <= 0.0 and _launch_t <= 0.0 and reward_hack == "" \
			and courier_goal == null and state != State.STAGGER

## Drives the GROUND POUND. Returns true on a tick it moved the body itself.
func _tick_pound(delta: float) -> bool:
	if pound == Pound.NONE:
		return false
	if not _pound_free():
		_end_pound()
		return false
	_pound_t -= delta
	_decelerate()
	_apply_gravity(delta)
	move_and_slide()
	match pound:
		Pound.WINDUP:
			# It faces the mark, not the target: stepping out is off its line too.
			var to := _pound_at - global_position
			to.y = 0.0
			_face_dir(to.normalized(), delta)
			if is_instance_valid(_ring_fill):
				var k := clampf(1.0 - _pound_t / POUND_WINDUP, 0.02, 1.0)
				_ring_fill.scale = Vector3(k, 1.0, k)
			if _pound_t <= 0.0:
				_slam()
		Pound.STUCK:
			if _pound_t <= 0.0:
				_end_pound()
	return true

## The fists land on the mark. Anyone still inside the ring is hit and thrown
## outward; a pound that hits nobody leaves the fists buried.
func _slam() -> void:
	_drop_ring()
	var hit := false
	if target != null and is_instance_valid(target):
		var off := target.global_position - _pound_at
		if Vector2(off.x, off.z).length() <= POUND_RADIUS and absf(off.y) < 2.0:
			hit = true
			var d = target.get_node_or_null("Damageable")
			if d:
				d.apply_damage(slam_damage, self)
			if target is CharacterBody3D:
				var away := target.global_position - global_position
				away.y = 0.0
				(target as CharacterBody3D).velocity += away.normalized() * 8.0 + Vector3.UP * 2.5
			if target.has_method("shake"):
				target.shake(0.45)
	# Heave forward onto the mark (stopping short of standing on it).
	var to := _pound_at - global_position
	to.y = 0.0
	if to.length() > 1.4:
		var v := to.normalized() * attack_lunge_speed
		velocity.x = v.x
		velocity.z = v.z
	recoil = 1.0 # the Punch clip
	spawn_shockwave_ring(POUND_RADIUS, RING_COLOR, _pound_at + Vector3.UP * 0.1, false)
	AudioBus.play_synth_at("impact_metal", _pound_at, 2.0, 0.55)
	AudioBus.play_synth_at("explosion", _pound_at, -8.0, 1.4)
	_attack_timer = attack_cooldown
	if hit:
		pound = Pound.NONE
	else:
		pound = Pound.STUCK
		_pound_t = POUND_STUCK

func _end_pound() -> void:
	pound = Pound.NONE
	_drop_ring()

## The floor under `at` (world layer), or `at` itself over a void.
func _floor_under(at: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at - Vector3.UP * 4.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else at

## The telegraph: a red rim of POUND_RADIUS on the floor at the mark, and a
## disc inside it that grows to the rim as the windup runs out. Unshaded, so
## the heat is in the albedo (values over 1 bloom).
func _spawn_ring() -> void:
	_drop_ring()
	var parent := get_tree().current_scene if get_tree().current_scene else get_parent()
	if parent == null:
		return
	_ring = Node3D.new()
	_ring.add_to_group("telegraph_ring")
	_ring.set_meta("radius", POUND_RADIUS)
	parent.add_child(_ring)
	_ring.global_position = _pound_at + Vector3.UP * 0.04
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = POUND_RADIUS - 0.14
	tm.outer_radius = POUND_RADIUS
	rim.mesh = tm
	rim.scale = Vector3(1.0, 0.15, 1.0)
	rim.material_override = _ring_material(Color(RING_COLOR.r * 3.0, RING_COLOR.g * 3.0, RING_COLOR.b * 3.0, 0.95))
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.add_child(rim)
	_ring_fill = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = POUND_RADIUS - 0.14
	cm.bottom_radius = POUND_RADIUS - 0.14
	cm.height = 0.02
	_ring_fill.mesh = cm
	_ring_fill.scale = Vector3(0.02, 1.0, 0.02)
	_ring_fill.material_override = _ring_material(Color(RING_COLOR.r * 1.6, RING_COLOR.g * 1.6, RING_COLOR.b * 1.6, 0.38))
	_ring_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.add_child(_ring_fill)

func _ring_material(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col
	return m

func _drop_ring() -> void:
	if is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null
	_ring_fill = null
