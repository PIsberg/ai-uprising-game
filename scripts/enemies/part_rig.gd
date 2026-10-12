class_name PartRig
extends RefCounted
## Rigid sub-part animation for static (unrigged) robot models: a GLB part is
## posed by a transform built in the robot's BODY frame, conjugated into the
## part's parent frame (so the fit, RobotModel's lean and any import scale
## between them carry through). Several Sketchfab GLBs merge a left and a
## right copy of a part into one mesh (RONIN's revolvers, the DOG's legs):
## `split_x` cuts such a mesh in two so each side can move on its own.

## A posable part: [MeshInstance3D, rest Transform3D, body->parent Transform3D].
## Taken once the model's fit has landed.
static func entry(body: Node3D, mi: MeshInstance3D) -> Array:
	var to_parent: Transform3D = (mi.get_parent() as Node3D).global_transform.affine_inverse() * body.global_transform
	return [mi, mi.transform, to_parent]

## Pose an entry by `lay`, a transform in the body frame.
static func pose(e: Array, lay: Transform3D) -> void:
	var to_parent := e[2] as Transform3D
	(e[0] as MeshInstance3D).transform = to_parent * lay * to_parent.affine_inverse() * (e[1] as Transform3D)

## Rotation by `angle` about the body-frame `axis` through `pivot`.
static func turn(pivot: Vector3, axis: Vector3, angle: float) -> Transform3D:
	var r := Basis(axis.normalized(), angle)
	return Transform3D(r, pivot - r * pivot)

## Cut `mi` at body-frame x = `mid` into a left (x < mid) and a right copy,
## each keeping the mesh's materials and the instance's overrides, and hide the
## original. Returns [left entry or null, right entry or null]. The copies join
## `body._mesh_instances` (hit flash) when the body has one.
static func split_x(body: Node3D, mi: MeshInstance3D, mid: float) -> Array:
	var xf := body.global_transform.affine_inverse() * mi.global_transform
	var out := [null, null]
	for side in 2:
		var am := ArrayMesh.new()
		var overrides: Array[Material] = []
		for si in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
			var keep := PackedInt32Array()
			for t in range(0, idx.size(), 3):
				var c: Vector3 = xf * ((v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0)
				if (c.x > mid) == (side == 1):
					keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
			if keep.is_empty():
				continue
			arr[Mesh.ARRAY_INDEX] = keep
			am.add_surface_from_arrays(mi.mesh.surface_get_primitive_type(si), arr)
			am.surface_set_material(am.get_surface_count() - 1, mi.mesh.surface_get_material(si))
			overrides.append(mi.get_surface_override_material(si))
		if am.get_surface_count() == 0:
			continue
		var copy := MeshInstance3D.new()
		copy.name = String(mi.name) + ("_R" if side == 1 else "_L")
		copy.mesh = am
		copy.material_override = mi.material_override
		for k in overrides.size():
			copy.set_surface_override_material(k, overrides[k])
		copy.transform = mi.transform
		mi.get_parent().add_child(copy)
		if "_mesh_instances" in body:
			(body.get("_mesh_instances") as Array).append(copy)
		out[side] = entry(body, copy)
	mi.visible = false
	return out

## Body-frame positions of the vertices `mi` draws (a split copy keeps the
## whole vertex array, so only indexed vertices count).
static func body_points(body: Node3D, mi: MeshInstance3D) -> PackedVector3Array:
	var xf := body.global_transform.affine_inverse() * mi.global_transform
	var out := PackedVector3Array()
	for si in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if arr[Mesh.ARRAY_INDEX] == null:
			for p in v:
				out.append(xf * p)
			continue
		var seen := {}
		for i in (arr[Mesh.ARRAY_INDEX] as PackedInt32Array):
			if not seen.has(i):
				seen[i] = true
				out.append(xf * v[i])
	return out

static func mean(points: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for p in points:
		c += p
	return c / maxf(points.size(), 1)
