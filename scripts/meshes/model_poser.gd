class_name ModelPoser
extends RefCounted
## Re-poses unrigged, flat-part GLB models by grouping mesh parts into a limb and
## swinging them about a pivot. The boss "giant_robot.glb" (PROMETHEUS-0 / TITAN)
## ships frozen in a stiff "hands raised, reaching forward" stance; the model has
## no skeleton, so each limb is just a loose cluster of MeshInstance3D parts. We
## bucket the left/right arm parts by region, reparent them under a shoulder pivot
## (preserving world transform), and rotate the pivot so the arms hang in a
## natural, slightly forward combat-ready stance instead.

## Lower the TITAN's raised arms into a natural resting stance.
## `mesh_root` is the instanced GLB scene root whose direct children are the
## ~120 "group####" MeshInstance3D parts (in the GLB's own local space).
static func pose_giant_robot_arms(mesh_root: Node3D) -> void:
	if mesh_root == null:
		return
	# Region thresholds in the GLB's local space (see tests/titan_pose_probe.gd
	# for the part dump these were derived from). Arms sit outboard of the torso
	# half-width and above mid-thigh; legs/hips fall below y_floor and are skipped.
	const X_ARM := 0.42      # |x| beyond this is an arm, not torso/spine
	const Y_FLOOR := -0.70   # below this is leg/foot, not arm
	var right_parts: Array[Node3D] = []
	var left_parts: Array[Node3D] = []
	for child in mesh_root.get_children():
		if not (child is MeshInstance3D):
			continue
		var mi := child as MeshInstance3D
		# Use the part's mesh centre (not just origin) so thin offset parts bucket
		# by where they actually sit.
		var c: Vector3 = mi.transform * mi.get_aabb().get_center()
		if c.y < Y_FLOOR:
			continue
		if c.x > X_ARM:
			right_parts.append(mi)
		elif c.x < -X_ARM:
			left_parts.append(mi)
	# Shoulder pivots, placed at each arm's actual root so the upper arm rotates
	# about the shoulder rather than translating.
	_swing_limb(mesh_root, right_parts, Vector3(0.60, 1.12, 0.10), Vector3(deg_to_rad(-74.0), 0.0, deg_to_rad(8.0)), "ArmPivotR")
	_swing_limb(mesh_root, left_parts, Vector3(-0.62, 1.10, 0.28), Vector3(deg_to_rad(-6.0), 0.0, deg_to_rad(16.0)), "ArmPivotL")

## For a RIGGED model whose clips bake the arms up, attach an ArmRelaxModifier to
## its Skeleton3D so the named bones get a fixed downward nudge after every clip.
## `bone_specs` is an Array of {"bone": String, "euler": Vector3} (degrees, local).
static func relax_skeleton_arms(model_root: Node, bone_specs: Array) -> ArmRelaxModifier:
	var sk := _find_skeleton(model_root)
	if sk == null:
		return null   # rigless model (e.g. the titan): nothing to relax, no-op
	var mod := ArmRelaxModifier.new()
	mod.name = "ArmRelax"
	mod.specs = bone_specs
	sk.add_child(mod)
	return mod

static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null

## Reparent `parts` under a fresh pivot at `pivot_local` (in mesh_root space) and
## apply `euler` rotation, keeping each part's world transform across the move.
static func _swing_limb(mesh_root: Node3D, parts: Array[Node3D], pivot_local: Vector3, euler: Vector3, pivot_name: String) -> void:
	if parts.is_empty():
		return
	var pivot := Node3D.new()
	pivot.name = pivot_name
	pivot.position = pivot_local
	mesh_root.add_child(pivot)
	for p in parts:
		p.reparent(pivot, true)   # keep global transform
	pivot.rotation = euler
