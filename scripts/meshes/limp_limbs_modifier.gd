class_name LimpLimbsModifier
extends SkeletonModifier3D
## A dead skinned robot's limbs go limp (#259). WreckBody throws the chassis
## as one rigid box, and until this the rig tumbled stiff in its last clip
## pose. Real PhysicalBone3D ragdolls do not work on these rigs: their
## skeletons sit under 41-270x import scales, and physical bones lose that
## scale (shapes, joints and anchors no longer match the drawn rig; a headless
## test drifted them ~100 m in 3 s). This is a cheaper secondary-motion
## ragdoll that needs no physics bodies and no scale: every limb bone keeps a
## WORLD direction that lags the tumbling chassis (inertia), is pulled toward
## gravity on a damped spring and weakly back toward its frozen pose (joint
## stiffness), stays inside a SWING_DEG cone of that pose, and is held above
## the floor under it. Directions are unit vectors, so the rig's scale never
## enters. Added by EnemyBase._classic_death_fx next to WreckBody, after the
## death has paused the clip and switched head tracking off.
## tests/limb_flop_probe.

## Bone-name fragments (lowercase) of the bones that flop, root to tip; IK
## helpers, pole targets, feet, fingers and _end bones never move.
const LIMB_BONES := ["upperarm", "lowerarm", "upperleg", "midleg", "lowerleg",
	"leg1", "leg2", "leg3", "neck", "head"]
const SKIP := ["_end", "_ik", "_pt", "pt.", "pole", "foot", "eye", "gun"]
const GRAVITY_K := 38.0  ## rad/s^2 per unit of misalignment with straight down
const POSE_K := 9.0      ## pull back toward the frozen pose
const DAMP := 5.5        ## 1/s
const SWING_DEG := 75.0  ## furthest a bone swings from its frozen pose
const FLOOR_GAP := 0.06  ## a limb tip stays this far above the floor under it

var _bones: Array = [] ## [{idx, dir: Vector3, vel: Vector3, len: float, below: Array[int]}], root to tip
var _built := false

## Attach to `sk` (a skinned robot's skeleton) if it has limbs to flop.
static func attach(sk: Skeleton3D) -> LimpLimbsModifier:
	if sk == null or not is_instance_valid(sk):
		return null
	var m := LimpLimbsModifier.new()
	m.name = "LimpLimbs"
	sk.add_child(m)
	return m

static func is_limb(bone_name: String) -> bool:
	var n := bone_name.to_lower()
	for s in SKIP:
		if n.contains(s):
			return false
	for l in LIMB_BONES:
		if n.contains(l):
			return true
	return false

func _build(sk: Skeleton3D) -> void:
	_built = true
	var g := sk.global_transform
	for i in sk.get_bone_count():
		if not is_limb(sk.get_bone_name(i)):
			continue
		var pose := sk.get_bone_global_pose(i)
		if pose.basis.get_scale().x < 0.01: # a severed limb (collapsed to its socket)
			continue
		var axis := (g.basis * pose.basis.y).normalized() # Blender bones point along +Y
		# Every bone below it (the floor check keeps the whole limb out of the
		# floor, not just the next joint: a thigh swung down drags the shin
		# with it), and the reach of the farthest one (world metres).
		var below: Array[int] = []
		var stack: Array = Array(sk.get_bone_children(i))
		while not stack.is_empty():
			var c: int = stack.pop_back()
			below.append(c)
			stack.append_array(Array(sk.get_bone_children(c)))
		var length := 0.0
		for c in below:
			length = maxf(length, ((g * sk.get_bone_global_pose(c)).origin - (g * pose).origin).length())
		_bones.append({"idx": i, "dir": axis, "vel": Vector3.ZERO, "len": length, "below": below})

func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if not _built:
		_build(sk)
	var dt := clampf(delta, 0.0, 0.05)
	var g := sk.global_transform
	var gq := g.basis.orthonormalized().get_rotation_quaternion()
	var space := sk.get_world_3d().direct_space_state if sk.is_inside_tree() else null
	for b in _bones:
		var idx: int = b["idx"]
		var pose := sk.get_bone_global_pose(idx)
		if pose.basis.get_scale().x < 0.01:
			continue
		# Where the frozen pose (with the parents' flop already applied) points.
		var base := (g.basis * pose.basis.y).normalized()
		var d: Vector3 = b["dir"]
		var w: Vector3 = b["vel"]
		w += (d.cross(Vector3.DOWN) * GRAVITY_K + d.cross(base) * POSE_K - w * DAMP) * dt
		var wl := w.length()
		if wl > 1e-6:
			d = Quaternion(w / wl, wl * dt) * d
		# Cone limit round the frozen pose.
		var swing := d.angle_to(base)
		var limit := deg_to_rad(SWING_DEG)
		if swing > limit:
			var ax := base.cross(d)
			if ax.length_squared() > 1e-8:
				d = Quaternion(ax.normalized(), limit) * base
			w *= 0.3
		var axis := base.cross(d)
		if axis.length_squared() < 1e-10:
			b["dir"] = d.normalized()
			b["vel"] = w
			continue
		axis = axis.normalized()
		var angle := base.angle_to(d)
		# Keep every joint below this one (a forearm ends in up to three palm
		# bones, off the bone's own axis; a thigh carries the shin) above the
		# floor under the joint. If the pose already reaches into it
		# (WreckBody's box is an approximation), the swing may not take it any
		# deeper.
		var joint := (g * pose).origin
		var length: float = b["len"]
		if space and length > 0.05:
			# From well above the joint: a ray that starts inside the floor finds nothing.
			var rq := PhysicsRayQueryParameters3D.create(joint + Vector3.UP * (length + 0.5), joint + Vector3.DOWN * (length + 1.0), 1)
			var hit := space.intersect_ray(rq)
			if hit:
				var offs: Array[Vector3] = []
				for c: int in b["below"]:
					offs.append((g * sk.get_bone_global_pose(c)).origin - joint)
				var floor_y: float = (hit.position as Vector3).y + FLOOR_GAP
				var allowed := minf(floor_y, _lowest(joint, offs, axis, 0.0))
				if _lowest(joint, offs, axis, angle) < allowed:
					var lo := 0.0
					var hi := angle
					for i in 6:
						var mid := (lo + hi) * 0.5
						if _lowest(joint, offs, axis, mid) < allowed:
							hi = mid
						else:
							lo = mid
					angle = lo
					d = Quaternion(axis, angle) * base
					w *= 0.3
		b["dir"] = d.normalized()
		b["vel"] = w
		if angle < 1e-5:
			continue
		# Turn the bone from `base` to `d` (a world rotation, carried into the
		# bone's parent space as in HeadTrackModifier).
		var q_world := Quaternion(axis, angle)
		var q := gq.inverse() * q_world * gq
		var par := sk.get_bone_parent(idx)
		var pq := Quaternion.IDENTITY
		if par >= 0:
			pq = sk.get_bone_global_pose(par).basis.orthonormalized().get_rotation_quaternion()
		var local := sk.get_bone_pose_rotation(idx)
		sk.set_bone_pose_rotation(idx, (pq.inverse() * q * pq * local).normalized())

## The lowest child joint height once the bone turns by `angle` about `axis`.
static func _lowest(joint: Vector3, offs: Array[Vector3], axis: Vector3, angle: float) -> float:
	var low := INF
	var q := Quaternion(axis, angle)
	for o in offs:
		low = minf(low, (joint + q * o).y)
	return low
