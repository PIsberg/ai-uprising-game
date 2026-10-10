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

const MAX_YAW_DEG := 70.0
const MAX_PITCH_UP_DEG := 50.0
const MAX_PITCH_DOWN_DEG := 40.0

var body: Node3D ## The enemy whose -Z is "straight ahead".
var look := Vector2.ZERO ## (pitch, yaw) radians, already clamped by RobotModel.
var _chain: Array = [] ## Array of {"idx": int, "share": float}, root to tip.

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

func _setup_chain() -> void:
	var sk := get_skeleton()
	_chain = chain_for(sk) if sk else []

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or body == null or not is_instance_valid(body):
		return
	if _chain.is_empty():
		_setup_chain()
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
