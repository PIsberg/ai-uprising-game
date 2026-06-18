class_name ArmRelaxModifier
extends SkeletonModifier3D
## Post-animation bone tweak for rigged models whose every clip bakes the arms
## into a raised "guard" pose (e.g. the GOLIATH-IX / George heavy mech). Runs
## after the AnimationPlayer poses the skeleton each frame and composes a small
## fixed rotation onto the named bones, so the arms drop to a natural carry while
## still inheriting the clip's arm-swing. Add as a child of the target Skeleton3D
## (see ModelPoser.relax_skeleton_arms).

## Bones to nudge, paired with a local-space euler rotation (degrees).
var specs: Array = []   # Array of {"bone": String, "euler": Vector3}

var _resolved: Array = []   # Array of {"idx": int, "quat": Quaternion}

func _setup() -> void:
	_resolved.clear()
	var sk := get_skeleton()
	if sk == null:
		return
	for s in specs:
		var idx := sk.find_bone(String(s.bone))
		if idx < 0:
			push_warning("ArmRelaxModifier: bone not found: %s" % s.bone)
			continue
		var e: Vector3 = s.euler
		var q := Quaternion.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))
		_resolved.append({"idx": idx, "quat": q})

func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _resolved.is_empty() and not specs.is_empty():
		_setup()
	for r in _resolved:
		var cur := sk.get_bone_pose_rotation(r.idx)
		# Post-multiply: rotate in the bone's own local frame, layered on the clip.
		sk.set_bone_pose_rotation(r.idx, cur * r.quat)
