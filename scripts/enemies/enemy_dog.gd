class_name EnemyDog
extends EnemyBase
## K-9 HUNTER — a four-legged robot attack-hound. Very fast, hunts in packs,
## sprints the gap and lunges into a bite. Fragile but relentless. Built model:
## assets/models/robots/robot_dog_v2.glb (RobotModel leans it; no walk rig).
## It trots on its legs: the GLB keeps upper legs, lower legs and paws as
## separate meshes (each holding the left and the right leg), so `_tick_gait`
## splits them per side (PartRig) and swings each leg about its hip axle,
## diagonal pairs together, stride matched to its ground speed; in the air it
## reaches forward with the front legs and trails the rear. Opt-in
## (`trot_gait`, set in dog.tscn): ORB and ROLLER extend this script with
## other models. tests/dog_gait_probe.
##
## Signature move: the POUNCE. From mid range it plants, rears back with jaws
## wide (a clear half-second tell — your window to shoot it out of the air),
## then springs in a flat arc and snaps its bite on landing.
##
## PACK HUNT (`pack_hunt`, set in dog.tscn): dogs on the same prey take turns.
## One dog at a time rears and pounces; the next may not start until PACK_GAP
## after it lands. The dogs waiting their turn run a ring CIRCLE_R out round
## the prey instead of standing in to bite. Every dog used to pounce on its own
## timer, so a pack of four landed four pounces in the same half second, and
## no sidestep answers that. tests/dog_pack_probe.

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

@export var pack_hunt: bool = false ## packs take turns pouncing and circle while they wait (dog.tscn only)
const PACK_GAP := 0.7 ## s after a pounce lands before a packmate may rear
const CIRCLE_R := 7.0 ## m from the prey the waiting dogs run their ring at
const CIRCLE_RANGE := 13.0 ## a dog further out than this just runs in
const CIRCLE_STEP := 0.6 ## rad ahead of itself on the ring a circling dog runs for
## Whose turn it is, per prey: target instance id -> {"dog": the EnemyDog that
## last reared at it, "free_at": the physics frame a packmate may rear from}.
static var _claims := {}
var circling := false ## this tick it ran the ring instead of its own AI
var _circle_dir := 1.0 ## +1 or -1: which way round
var _circle_flip_cd := 0.0
var _landed_frame := -100000 ## physics frame of this dog's last landing

@export var trot_gait: bool = false ## robot_dog_v2's leg parts trot (dog.tscn only)
# Leg parts and hip axles as named in robot_dog_v2.glb (front is -z).
const LEG_FRONT := ["Box003", "Box004", "Sphere002"]
const LEG_REAR := ["Box005", "Box006", "Sphere003"]
const AXLE_FRONT := "Cylinder001"
const AXLE_REAR := "Cylinder002"
const STRIDE := 1.1      ## m of ground per gait cycle
const SWING := 0.45      ## rad each leg swings either side at a run
const AIR_REACH := 0.7   ## rad front legs reach forward in the air (rear trail 0.85x)
var _gait_ready := false
var _legs: Array = []    ## {entries, pivot, offset, front}
var _gait_phase := 0.0
var _gait_amp := 0.0
var _air_w := 0.0

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
	_circle_dir = 1.0 if get_instance_id() % 2 == 0 else -1.0 # a pack splits both ways round

## Rear-back → spring → landing bite, layered over the base ground AI the same
## way the ravager's leap is. Airborne and during the windup it's a clean shot.
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if trot_gait:
		_tick_gait(delta)
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
	circling = _should_circle()
	if circling:
		_tick_circle(delta)
		return
	super._physics_process(delta)
	if target and _pounce_cd <= 0.0 and is_on_floor() \
			and state in [State.CHASE, State.ATTACK]:
		var dist := global_position.distance_to(target.global_position)
		if dist >= pounce_min and dist <= pounce_max and _can_see(target) and _turn_free():
			if pack_hunt:
				_claims[target.get_instance_id()] = {"dog": self, "free_at": 0}
			_pounce_windup_t = pounce_windup
			recoil = 0.6
			AudioBus.play_synth_at("overlord_glitch", global_position, -8.0, 1.9)

## The packmate whose pounce is under way at this dog's prey (rearing or in
## the air), or null. A dead or freed holder holds nothing.
func _pack_pouncer() -> EnemyDog:
	if not pack_hunt or target == null or not is_instance_valid(target):
		return null
	var c: Variant = _claims.get(target.get_instance_id())
	if c == null:
		return null
	var holder: Variant = c["dog"]
	if not is_instance_valid(holder) or holder == self or holder.state == State.DEAD:
		return null
	return holder if (holder._pouncing or holder._pounce_windup_t > 0.0) else null

## True when this dog may rear: nobody else's pounce is under way at its prey
## and PACK_GAP has passed since the last one landed.
func _turn_free() -> bool:
	if not pack_hunt:
		return true
	if _pack_pouncer() != null:
		return false
	var c: Variant = _claims.get(target.get_instance_id())
	if c == null or not is_instance_valid(c["dog"]) or c["dog"] == self:
		return true
	# The dog that pounced longest ago goes first: one fresh off a pounce holds
	# back up to a third of a second more, so the turn goes round the pack.
	var now := Engine.get_physics_frames()
	var hold := clampi(20 - (now - _landed_frame) / 20, 0, 20)
	return now >= int(c["free_at"]) + hold

## A dog waits its turn on the ring while a packmate's pounce is under way (or
## has just landed) and it is close enough to be part of the hunt. Nothing else
## may have the body: an EMP, a throw, a hijack, a rewrite, a courier run.
func _should_circle() -> bool:
	if not pack_hunt or target == null or not is_instance_valid(target):
		return false
	if state != State.CHASE and state != State.ATTACK:
		return false
	if _emp_t > 0.0 or _launch_t > 0.0 or hijacked or rogue or reward_hack != "" or courier_goal != null:
		return false
	if not is_on_floor() or _turn_free():
		return false
	return global_position.distance_to(target.global_position) <= CIRCLE_RANGE

## Run the ring: head for the point CIRCLE_STEP further round the prey at
## CIRCLE_R, on the navmesh (so walls and hazard beds are gone round, not
## through). Where the ring leaves the navmesh, or a wall stops it, it turns
## and goes round the other way.
func _tick_circle(delta: float) -> void:
	_circle_flip_cd = maxf(0.0, _circle_flip_cd - delta)
	_pounce_cd = maxf(_pounce_cd, 0.0)
	var dest := _ring_point()
	var map := get_world_3d().navigation_map
	var on_nav := NavigationServer3D.map_get_closest_point(map, dest)
	var off := Vector2(on_nav.x - dest.x, on_nav.z - dest.z).length()
	if (off > 1.5 or is_on_wall()) and _circle_flip_cd <= 0.0:
		_circle_dir = -_circle_dir
		_circle_flip_cd = 0.8
		dest = _ring_point()
		on_nav = NavigationServer3D.map_get_closest_point(map, dest)
		off = Vector2(on_nav.x - dest.x, on_nav.z - dest.z).length()
	_move_toward(on_nav if off <= 1.5 else dest, delta)
	_apply_gravity(delta)
	move_and_slide()

func _ring_point() -> Vector3:
	var to := global_position - target.global_position
	to.y = 0.0
	if to.length() < 0.1:
		to = Vector3.FORWARD
	var ang := atan2(to.z, to.x) + CIRCLE_STEP * _circle_dir
	return target.global_position + Vector3(cos(ang), 0.0, sin(ang)) * CIRCLE_R

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
	_landed_frame = Engine.get_physics_frames()
	# The pack's next pounce waits PACK_GAP from this landing.
	if pack_hunt and target != null and is_instance_valid(target):
		var c: Variant = _claims.get(target.get_instance_id())
		if c != null and is_instance_valid(c["dog"]) and c["dog"] == self:
			c["free_at"] = Engine.get_physics_frames() + int(PACK_GAP * Engine.physics_ticks_per_second)
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

## Split the legs per side and find each hip, once RobotModel's fit has landed.
func _setup_gait() -> void:
	var paw := find_child(LEG_FRONT[2], true, false) as Node3D
	if paw == null or not paw.is_visible_in_tree():
		return
	for front in [true, false]:
		var axle := find_child(AXLE_FRONT if front else AXLE_REAR, true, false)
		if axle == null:
			trot_gait = false
			return
		var hip := PackedVector3Array()
		for m in axle.find_children("*", "MeshInstance3D", true, false):
			hip.append_array(PartRig.body_points(self, m as MeshInstance3D))
		var axis_c := PartRig.mean(hip)
		var sides: Array = [[], []]
		var xs: Array = [PackedVector3Array(), PackedVector3Array()]
		for n in (LEG_FRONT if front else LEG_REAR):
			var node := find_child(n, true, false)
			if node == null:
				trot_gait = false
				return
			for m in node.find_children("*", "MeshInstance3D", true, false):
				var halves := PartRig.split_x(self, m as MeshInstance3D, 0.0)
				for side in 2:
					if halves[side] != null:
						(sides[side] as Array).append(halves[side])
						xs[side] = (xs[side] as PackedVector3Array) + PartRig.body_points(self, halves[side][0])
		for side in 2:
			# Trot: front-left with rear-right, front-right with rear-left.
			var offset := 0.0 if (side == 0) == front else PI
			var pivot := Vector3(PartRig.mean(xs[side]).x, axis_c.y, axis_c.z)
			_legs.append({"entries": sides[side], "pivot": pivot, "offset": offset, "front": front})
	_gait_ready = true

## Swing each leg about its hip: a trot whose cadence follows ground speed,
## legs back under it at rest, stretched out (reach and trail) in the air.
func _tick_gait(delta: float) -> void:
	if not _gait_ready:
		_setup_gait()
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var air := not is_on_floor()
	_gait_phase = fposmod(_gait_phase + delta * speed / STRIDE * TAU, TAU)
	var want := 0.0 if air else SWING * clampf(speed / 4.0, 0.0, 1.0)
	_gait_amp = move_toward(_gait_amp, want, delta * 3.0)
	_air_w = move_toward(_air_w, 1.0 if air else 0.0, delta * 6.0)
	for leg in _legs:
		var reach := AIR_REACH if leg["front"] else -AIR_REACH * 0.85
		var angle := sin(_gait_phase + float(leg["offset"])) * _gait_amp + _air_w * reach
		var lay := PartRig.turn(leg["pivot"], Vector3.RIGHT, angle)
		for e in leg["entries"]:
			PartRig.pose(e, lay)
