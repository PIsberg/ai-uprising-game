class_name EnemySniper
extends EnemyBase
## A long-range emplacement that plays completely differently from the rushers:
## it barely moves, sees far, and kills with a heavy hitscan beam — but only
## after a visible charge-up. Break line of sight during the charge and the shot
## misses, so it pressures the player to use cover and flank rather than peek.
## Its model (Quaternius "QuadShell") is a shell on four long walking legs with
## a short gun barrel on each side: each beam leaves the front of one barrel,
## alternating, and after every shot it gets up and walks to a new spot a few
## metres to the side (shoot and scoot) before it plants for the next charge.

@export var charge_time: float = 1.3
@export var beam_damage: float = 42.0

const BARRELS := ["Gun.L", "Gun.R"]
const BARREL_FWD := 0.83    ## Gun bone to the barrel's front face (m, body forward)
const SCOOT_MIN := 6.0      ## sideways relocation after a shot (m)
const SCOOT_MAX := 9.0
const SCOOT_MULT := 3.0     ## x chase speed: 1.6 -> 4.8 m/s on its long legs
const SCOOT_TIME := 2.5     ## gives up on the walk after this
const SCOOT_DELAY := 0.35   ## the shot's recoil (Attack clip, 0.33 s) plays out planted

var _charging: bool = false
var _charge_t: float = 0.0
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _barrel_att: Array = [] ## BoneAttachment3D per barrel
var _barrel_off: Array = [] ## each barrel's front face in its bone's frame
var _barrel_i: int = 0
var _scoot_to: Vector3
var _scoot_t: float = 0.0   ## >0: walking to _scoot_to
var _scoot_wait: float = 0.0 ## >0: still planted after the shot, walk pending

func _ready() -> void:
	max_health = 90.0
	move_speed = 1.6
	turn_speed = 4.0
	sight_range = 60.0
	sight_angle_deg = 80.0
	attack_range = 55.0
	preferred_range = 34.0
	attack_cooldown = 3.6
	telegraph_time = 0.0 # the charged beam is its own (longer) tell — no generic wind-up
	score_value = 220
	super._ready()
	_rig_barrels()

## One unscaled muzzle (muzzle_on_bone) that hops between the two barrels: the
## base follows whichever attachment `_muzzle_bone` names, plus its offset.
## The offsets are the barrel's front face measured in each Gun bone's frame,
## so the beam stays on the barrel when the Charge clip moves the guns.
func _rig_barrels() -> void:
	if not muzzle_on_bone(BARRELS[0]):
		return
	var sk := _muzzle_bone.get_parent() as Skeleton3D
	var right := BoneAttachment3D.new()
	right.bone_name = BARRELS[1]
	sk.add_child(right)
	_barrel_att = [_muzzle_bone, right]
	var ahead: Vector3 = global_transform.basis.orthonormalized() * Vector3(0.0, 0.0, -BARREL_FWD)
	for bone in BARRELS:
		var pose: Transform3D = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone))
		_barrel_off.append(pose.basis.orthonormalized().inverse() * ahead)
		# Both guns swing onto the target (pivoting on their own bone).
		add_gun_bone(sk, sk.find_bone(bone), _barrel_off[-1])
	_use_barrel(0)

func _use_barrel(i: int) -> void:
	if _barrel_att.is_empty():
		return
	_barrel_i = i
	_muzzle_bone = _barrel_att[i]
	_muzzle_offset = _barrel_off[i]
	muzzle.global_position = bone_point(_muzzle_bone, _muzzle_offset)

## Shoot and scoot: a walk in progress owns the body (the charge never starts
## mid-walk, since the base attack logic is skipped); a stagger or losing the
## fight ends it.
func _run_state(delta: float) -> void:
	if _scoot_t > 0.0 and not _charging and state == State.ATTACK:
		if _scoot_wait > 0.0:
			_scoot_wait -= delta
			_decelerate()
			_face_target(delta)
			return
		_scoot_t -= delta
		var flat := _scoot_to - global_position
		flat.y = 0.0
		if flat.length() > 1.0:
			# Crab-walk: the legs carry it sideways while the shell (and its
			# 80-degree sight cone) stays on the target.
			var yaw := rotation.y
			_move_toward(_scoot_to, delta)
			rotation.y = yaw
			_face_target(delta)
			var h := Vector2(velocity.x, velocity.z)
			if h.length() > 0.1:
				h = h.normalized() * chase_speed() * SCOOT_MULT
				velocity.x = h.x
				velocity.z = h.y
			return
		_scoot_t = 0.0
	if _scoot_t <= 0.0 and Vector2(velocity.x, velocity.z).length() > move_speed * 1.5:
		_decelerate() # planted: the walk's momentum stops here, not in a slide
	if state != State.ATTACK:
		_scoot_t = 0.0
	super._run_state(delta)

## A spot SCOOT_MIN..MAX to one side of the line to the target, on the navmesh;
## the other side if that one is off the mesh, none if both are.
func _start_scoot() -> void:
	if target == null or not is_instance_valid(target):
		return
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length() < 0.1:
		return
	var side := to.normalized().cross(Vector3.UP)
	var first := 1.0 if randf() < 0.5 else -1.0
	var dist := randf_range(SCOOT_MIN, SCOOT_MAX)
	var map := get_world_3d().navigation_map
	for s in [first, -first]:
		var want: Vector3 = global_position + side * s * dist
		var got := NavigationServer3D.map_get_closest_point(map, want)
		if Vector2(got.x - want.x, got.z - want.z).length() < 1.5:
			_scoot_to = got
			_scoot_t = SCOOT_TIME
			_scoot_wait = SCOOT_DELAY
			return

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_tick_charge(delta)
	# The eye lamp glows brighter as the shot charges (the visible weakpoint tell).
	var lamp := get_node_or_null("Eye/EyeLight") as OmniLight3D
	if lamp:
		var goal := 1.5 + (5.0 * (_charge_t / charge_time) if _charging else 0.5 * sin(_state_timer * 3.0))
		lamp.light_energy = move_toward(lamp.light_energy, goal, delta * 25.0)

## A stagger interrupts the charge — the shot fizzles and the beam drops.
func _on_staggered() -> void:
	_charging = false
	_hide_beam()

## Begins a charged shot instead of firing instantly.
func _perform_attack() -> void:
	if _charging or target == null:
		return
	_charging = true
	_charge_t = 0.0
	_use_barrel((_barrel_i + 1) % 2) # alternate barrels shot to shot
	_ensure_beam()
	# Crouch into the QuadShell's charge-up clip, stretched over the whole
	# charge (play_named's clip was taken back by idle on the next tick, #242).
	var model := get_node_or_null("Model")
	if model and model.has_method("play_oneshot_over"):
		model.play_oneshot_over("Charge", charge_time)
	if has_node("/root/AudioBus"):
		var ab: Node = get_node("/root/AudioBus")
		if ab.has_method("play_synth_at"):
			ab.play_synth_at("drone_hum", global_position, -4.0, 1.4)

## Advances a charging shot; aims the telegraph at the target and fires (or
## fizzles, if line of sight was lost) when the charge completes.
func _tick_charge(delta: float) -> void:
	if not _charging:
		return
	_charge_t += delta
	_aim_beam(false)
	if _charge_t >= charge_time:
		_charging = false
		_fire_beam()

func _ensure_beam() -> void:
	if _beam != null:
		return
	_beam = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.04, 0.04, 1.0)
	_beam.mesh = bm
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.albedo_color = Color(1.0, 0.2, 0.15, 0.0)
	_beam_mat.emission_enabled = true
	_beam_mat.emission = Color(1.0, 0.25, 0.18)
	_beam_mat.emission_energy_multiplier = 6.0
	_beam.material_override = _beam_mat
	_beam.top_level = true # position in world space directly
	add_child(_beam)

## Stretches/aims the telegraph beam from the muzzle to the target. `hot` makes
## it the bright firing flash; otherwise it's the dim charging line.
func _aim_beam(hot: bool) -> void:
	if _beam == null or target == null or muzzle == null:
		return
	var from: Vector3 = muzzle.global_position
	var to: Vector3 = target.global_position + Vector3.UP * 0.4
	var mid := (from + to) * 0.5
	var dist := from.distance_to(to)
	_beam.global_position = mid
	if dist > 0.01:
		_beam.look_at(to, Vector3.UP)
	_beam.scale = Vector3(1.0, 1.0, dist)
	var charge_frac := clampf(_charge_t / charge_time, 0.0, 1.0)
	var width := (1.0 if hot else 0.25 + charge_frac * 0.5)
	_beam.scale.x = width
	_beam.scale.y = width
	_beam_mat.albedo_color.a = (0.9 if hot else 0.15 + charge_frac * 0.45)
	_beam_mat.emission_energy_multiplier = (12.0 if hot else 6.0)

func _fire_beam() -> void:
	if target == null or muzzle == null:
		_hide_beam()
		return
	var from: Vector3 = muzzle.global_position # the barrel the beam is drawn from
	var to: Vector3 = target.global_position + Vector3.UP * 0.4
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 0b0000011 # world + player
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	# Only connects if the ray actually reaches the player (LOS not broken).
	if hit and hit.get("collider") and (hit["collider"] as Node).is_in_group("player"):
		var d = (hit["collider"] as Node).get_node_or_null("Damageable")
		if d:
			d.apply_damage(beam_damage, self)
	_aim_beam(true)
	if has_node("/root/AudioBus"):
		var ab: Node = get_node("/root/AudioBus")
		if ab.has_method("play_synth_at"):
			ab.play_synth_at("rifle_fire", muzzle.global_position, 2.0, 0.7)
	recoil = 1.0
	_start_scoot()
	# Flash fades out fast.
	var tw := _beam.create_tween()
	tw.tween_property(_beam_mat, "albedo_color:a", 0.0, 0.2)
	tw.tween_callback(_hide_beam)

func _hide_beam() -> void:
	if _beam_mat:
		_beam_mat.albedo_color.a = 0.0
