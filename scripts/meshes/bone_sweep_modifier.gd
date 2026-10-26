class_name BoneSweepModifier
extends SkeletonModifier3D
## Post-animation rigid sweeps for a skinned robot, on top of whatever clip
## is playing, built in the robot's BODY frame:
##  - `sweep` turns a bone by a fixed quaternion about a pivot bone's origin
##    (its own, or a hip for a foot the rig keeps as a separate IK target);
##  - `point` turns a bone so the line from it to a tip bone, as the clip
##    has it this frame, lies along a body-frame direction (then an extra
##    turn, a kick), whatever pose the clip put the limb in;
##  - `follow` turns a bone by the turn just worked out for another, about
##    that bone's origin (the IK foot and pole target of a pointed leg).
## The FISHBOT trails its lander legs behind it and kicks them with its tail
## beat this way; HeadTrackModifier does heads and gun arms. Entries apply
## in the order they were added, so a led bone comes after its leader.
## `weight` eases the whole set in and out (0 = the clip's pose). The
## skeleton hands the clip's pose back once the frame is drawn, so the swept
## poses are kept here (`posed`) for anything that needs to read them.

var body: Node3D           ## the enemy whose -Z is "straight ahead"
var weight := 1.0
var _entries: Array = []   ## [{"idx", "pivot", "q", "tip", "dir", "lead"}]
var _out := {}             ## bone idx -> skeleton-space pose as last swept
var _out_frame := -1

## Turn `bone` by `q_body` about `pivot_bone`'s origin (its own when empty).
func sweep(bone: String, q_body: Quaternion, pivot_bone: String = "") -> bool:
	return _register(bone, pivot_bone if pivot_bone != "" else bone, q_body, "", Vector3.ZERO, "")

## Turn `bone` about its origin so its line to `tip_bone` lies along
## `dir_body`, then by `extra` (a kick about the same origin).
func point(bone: String, tip_bone: String, dir_body: Vector3, extra: Quaternion = Quaternion.IDENTITY) -> bool:
	return _register(bone, bone, extra, tip_bone, dir_body, "")

## Turn `bone` by whatever turn `lead_bone` got this frame, about
## `lead_bone`'s origin.
func follow(bone: String, lead_bone: String) -> bool:
	return _register(bone, lead_bone, Quaternion.IDENTITY, "", Vector3.ZERO, lead_bone)

## Returns false, with nothing registered, when any named bone is missing.
func _register(bone: String, pivot_bone: String, q: Quaternion, tip_bone: String, dir: Vector3, lead_bone: String) -> bool:
	var sk := get_skeleton()
	if sk == null:
		return false
	var idx := sk.find_bone(bone)
	var pivot := sk.find_bone(pivot_bone)
	var tip := sk.find_bone(tip_bone) if tip_bone != "" else -1
	var lead := sk.find_bone(lead_bone) if lead_bone != "" else -1
	if idx < 0 or pivot < 0 or (tip_bone != "" and tip < 0) or (lead_bone != "" and lead < 0):
		return false
	var e := {"idx": idx, "pivot": pivot, "q": q, "tip": tip, "dir": dir, "lead": lead}
	for i in _entries.size():
		if _entries[i]["idx"] == idx:
			_entries[i] = e
			return true
	_entries.append(e)
	return true

## The pose (skeleton space) `bone` was last swept to, or the skeleton's
## current pose of it when the sweep has not run in the last two frames.
func posed(bone: String) -> Transform3D:
	var sk := get_skeleton()
	var idx := sk.find_bone(bone) if sk else -1
	if idx < 0:
		return Transform3D.IDENTITY
	if _out.has(idx) and Engine.get_process_frames() - _out_frame <= 2:
		return _out[idx]
	return sk.get_bone_global_pose(idx)

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or body == null or not is_instance_valid(body) or weight <= 0.0 or _entries.is_empty():
		return
	# Body-frame turns carried into skeleton space, as HeadTrackModifier does.
	var to_skel := sk.global_transform.basis.orthonormalized().get_rotation_quaternion().inverse() \
		* body.global_transform.basis.orthonormalized().get_rotation_quaternion()
	var to_body := to_skel.inverse()
	var turned := {} # idx -> this frame's body-frame turn
	for e in _entries:
		var idx: int = e["idx"]
		var q_body: Quaternion = e["q"]
		if e["lead"] >= 0:
			q_body = turned.get(e["lead"], Quaternion.IDENTITY)
		elif e["tip"] >= 0:
			var from: Vector3 = to_body * (sk.get_bone_global_pose(e["tip"]).origin - sk.get_bone_global_pose(idx).origin)
			var dir: Vector3 = e["dir"]
			if from.length_squared() > 1e-6 and dir.length_squared() > 1e-6:
				q_body = (e["q"] as Quaternion) * Quaternion(from.normalized(), dir.normalized())
		turned[idx] = q_body
		var r := Basis(to_skel * Quaternion.IDENTITY.slerp(q_body, weight) * to_body)
		var pivot: Vector3 = sk.get_bone_global_pose(e["pivot"]).origin
		var pose: Transform3D = Transform3D(r, pivot - r * pivot) * sk.get_bone_global_pose(idx)
		sk.set_bone_global_pose(idx, pose)
		_out[idx] = pose
	_out_frame = Engine.get_process_frames()
