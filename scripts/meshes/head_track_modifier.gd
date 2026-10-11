class_name HeadTrackModifier
extends SkeletonModifier3D
## Post-animation look-at for skinned robots: turns the head (and the torso,
## chest and neck where the rig has them) toward what the robot is fighting, on
## top of whatever clip is playing, so a walking or idling robot visibly tracks
## the player and tilts up at you on a ledge instead of staring at the horizon.
## RobotModel owns the aim: it eases `look` (pitch, yaw in radians, relative to
## the body's -Z facing) toward the target and back to zero, and switches the
## modifier off at rest and on death. This node only turns that into bone poses.
##
## Rig-agnostic: the turn is built in the BODY's frame and carried into skeleton
## space, then split across the chain so the head ends up rotated by the whole
## turn whatever local axis each rig's bones use. Every share is a power of the
## same quaternion, so the shares commute and each bone only needs its parent's
## global pose: local' = P^-1 * Q^share * P * local.
##
## Gun arms (issue #232): after the head, each registered arm swings from its
## pivot (a turret Gun bone, or the upper arm of a shooting hand) so the line
## pivot -> muzzle passes through `aim_point`, scaled by `arm_weight`. The
## skeleton hands the clip pose back once the frame is drawn, so the muzzle
## bones' aimed poses are kept here (`rendered_pose`) for the shots to leave from.

const MAX_YAW_DEG := 70.0
const MAX_PITCH_UP_DEG := 50.0
const MAX_PITCH_DOWN_DEG := 40.0
const MAX_ARM_DEG := 95.0 ## a lowered arm can come all the way up to the target

var body: Node3D ## The enemy whose -Z is "straight ahead".
var look := Vector2.ZERO ## (pitch, yaw) radians, already clamped by RobotModel.
var aim_point := Vector3.ZERO ## World point the gun arms aim at.
var arm_weight := 0.0 ## 0 = the clip's arm pose, 1 = on target. Eased by RobotModel.
var _chain: Array = [] ## Array of {"idx": int, "share": float}, root to tip.
var _chain_built := false
var _arms: Array = [] ## Array of {"root": int, "tip": int, "offset": Vector3}.
var _tips: Array[int] = [] ## Bones whose rendered pose the muzzle follows.
var _tip_pose := {} ## tip idx -> skeleton-space pose as last rendered
var _tip_frame := -1

## The bones to turn and each one's share of the turn, or [] when the rig has no
## head. Torso/chest/neck take a little each so the turn rolls up the spine.
static func chain_for(sk: Skeleton3D) -> Array:
	var head := -1
	var spine: Array[int] = []
	for i in sk.get_bone_count():
		var nm := sk.get_bone_name(i).to_lower()
		if nm.contains("end") or nm.contains("top"):
			continue
		if nm.contains("head"):
			if head < 0:
				head = i
		elif nm.contains("torso") or nm.contains("chest") or nm.contains("spine") or nm.contains("neck"):
			spine.append(i)
	if head < 0:
		return []
	# Only spine bones that are ancestors of the head: a twin-headed or tailed
	# rig must not twist a limb that merely shares a name.
	var ancestors: Array[int] = []
	var p := sk.get_bone_parent(head)
	while p >= 0:
		ancestors.append(p)
		p = sk.get_bone_parent(p)
	var out: Array = []
	var used := 0.0
	ancestors.reverse()
	for a in ancestors:
		if a in spine:
			out.append({"idx": a, "share": 0.18})
			used += 0.18
	out.append({"idx": head, "share": maxf(1.0 - used, 0.4)})
	return out

## The bone a gun swings from when it is fired from `tip`, or -1 when the tip
## already turns with the head (a lens in the head, cannons on the torso). The
## arm is everything between the tip and the first bone the look chain turns,
## or the bone the arm shares with the head (the body): a turret Gun bone on
## the Body pivots on itself, a hand pivots at its upper arm. A clavicle
## ("Shoulder") above the upper arm is skipped: swinging it shrugs the arm.
static func arm_root_for(sk: Skeleton3D, tip: int, chain: Array) -> int:
	if tip < 0:
		return -1
	var stops := {}
	for link in chain:
		var a: int = link["idx"]
		while a >= 0:
			stops[a] = true
			a = sk.get_bone_parent(a)
	if stops.has(tip):
		return -1
	var path: Array[int] = [tip]
	var p := sk.get_bone_parent(tip)
	while p >= 0 and not stops.has(p) and sk.get_bone_parent(p) >= 0:
		path.append(p)
		p = sk.get_bone_parent(p)
	if path.size() > 1 and sk.get_bone_name(path[-1]).to_lower().contains("shoulder"):
		path.pop_back()
	return path[-1]

## Follow `tip` for the muzzle and, when `aim`, swing its arm onto aim_point.
## `offset` is the muzzle in the tip bone's frame (metres, scale stripped), as
## EnemyBase.bone_point takes it. A gun that pivots on its own muzzle bone with
## no offset has no barrel to aim and is only followed.
func add_gun(tip: int, offset: Vector3, aim: bool) -> void:
	var sk := get_skeleton()
	if sk == null or tip < 0:
		return
	if not tip in _tips:
		_tips.append(tip)
	_arms = _arms.filter(func(a: Dictionary) -> bool: return a["tip"] != tip)
	if not aim:
		return
	_ensure_chain()
	var root := arm_root_for(sk, tip, _chain)
	if root < 0 or (root == tip and offset.is_zero_approx()):
		return
	_arms.append({"root": root, "tip": tip, "offset": offset})

func has_arms() -> bool:
	return not _arms.is_empty()

## The pose (skeleton space) `idx` was last drawn in, aim included, or
## `fallback` (the clip's) when this modifier is not running.
func rendered_pose(idx: int, fallback: Transform3D) -> Transform3D:
	if not active or not _tip_pose.has(idx) or Engine.get_process_frames() - _tip_frame > 2:
		return fallback
	return _tip_pose[idx]

func _ensure_chain() -> void:
	if _chain_built:
		return
	_chain_built = true
	var sk := get_skeleton()
	if _chain.is_empty() and sk:
		_chain = chain_for(sk)

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or body == null or not is_instance_valid(body):
		return
	_ensure_chain()
	_turn_head(sk)
	if arm_weight > 0.0:
		for arm in _arms:
			_aim_arm(sk, arm)
	if not _tips.is_empty():
		for idx in _tips:
			_tip_pose[idx] = sk.get_bone_global_pose(idx)
		_tip_frame = Engine.get_process_frames()

## Swing the arm's pivot so pivot -> muzzle lines up with pivot -> aim_point,
## by arm_weight and at most MAX_ARM_DEG. Worked in world space (bone_point's
## frame for the offset), applied in skeleton space like the head turn.
func _aim_arm(sk: Skeleton3D, arm: Dictionary) -> void:
	var root: int = arm["root"]
	var g := sk.global_transform
	var pivot := (g * sk.get_bone_global_pose(root)).origin
	var tip_w := g * sk.get_bone_global_pose(arm["tip"])
	var muzzle: Vector3 = tip_w.origin + tip_w.basis.orthonormalized() * (arm["offset"] as Vector3)
	var u := muzzle - pivot
	var v := aim_point - pivot
	if u.length_squared() < 1e-6 or v.length_squared() < 1e-4:
		return
	u = u.normalized()
	v = v.normalized()
	var axis := u.cross(v)
	if axis.length_squared() < 1e-8:
		return
	var angle := minf(u.angle_to(v), deg_to_rad(MAX_ARM_DEG)) * clampf(arm_weight, 0.0, 1.0)
	var gq := g.basis.orthonormalized().get_rotation_quaternion()
	var q := gq.inverse() * Quaternion(axis.normalized(), angle) * gq
	var par := sk.get_bone_parent(root)
	var pq := Quaternion.IDENTITY
	if par >= 0:
		pq = sk.get_bone_global_pose(par).basis.orthonormalized().get_rotation_quaternion()
	var local := sk.get_bone_pose_rotation(root)
	sk.set_bone_pose_rotation(root, (pq.inverse() * q * pq * local).normalized())

func _turn_head(sk: Skeleton3D) -> void:
	if _chain.is_empty():
		return
	# The turn in the body's frame (yaw then pitch), carried into skeleton space.
	var q_body := Quaternion.from_euler(Vector3(look.x, look.y, 0.0))
	var to_skel := sk.global_transform.basis.orthonormalized().get_rotation_quaternion().inverse() \
		* body.global_transform.basis.orthonormalized().get_rotation_quaternion()
	var q := to_skel * q_body * to_skel.inverse()
	for link in _chain:
		var idx: int = link["idx"]
		var share := Quaternion.IDENTITY.slerp(q, float(link["share"]))
		var par := sk.get_bone_parent(idx)
		var pq := Quaternion.IDENTITY
		if par >= 0:
			pq = sk.get_bone_global_pose(par).basis.orthonormalized().get_rotation_quaternion()
		var local := sk.get_bone_pose_rotation(idx)
		sk.set_bone_pose_rotation(idx, (pq.inverse() * share * pq * local).normalized())
