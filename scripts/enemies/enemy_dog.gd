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
	super._physics_process(delta)
	if target and _pounce_cd <= 0.0 and is_on_floor() \
			and state in [State.CHASE, State.ATTACK]:
		var dist := global_position.distance_to(target.global_position)
		if dist >= pounce_min and dist <= pounce_max and _can_see(target):
			_pounce_windup_t = pounce_windup
			recoil = 0.6
			AudioBus.play_synth_at("overlord_glitch", global_position, -8.0, 1.9)

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
