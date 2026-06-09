@tool
class_name BeveledBoxMesh
extends PrimitiveMesh
## A box with chamfered edges. Plain BoxMesh primitives read as "programmer
## art" because their edges catch no light; a small 45° bevel gives every edge
## a specular highlight, which is most of what makes hard-surface models look
## machined instead of extruded. Drop-in replacement for BoxMesh (same `size`
## and per-mesh `material`).

@export var size: Vector3 = Vector3.ONE:
	set(v):
		size = v
		request_update()
## Chamfer width. Clamped so it can never exceed half the smallest dimension.
@export_range(0.0, 1.0, 0.001, "or_greater") var bevel: float = 0.03:
	set(v):
		bevel = v
		request_update()

func _create_mesh_array() -> Array:
	var h := size * 0.5
	var b: float = clampf(bevel, 0.0, minf(h.x, minf(h.y, h.z)) * 0.49)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	# For each of the 8 corners there are three "inset" points, one per axis,
	# where a face meets its chamfer. Everything below is stitched from these.
	var px := {}
	var py := {}
	var pz := {}
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var k := Vector3(sx, sy, sz)
				px[k] = Vector3(sx * h.x, sy * (h.y - b), sz * (h.z - b))
				py[k] = Vector3(sx * (h.x - b), sy * h.y, sz * (h.z - b))
				pz[k] = Vector3(sx * (h.x - b), sy * (h.y - b), sz * h.z)

	var add_poly := func(pts: Array, n: Vector3) -> void:
		n = n.normalized()
		# Self-correcting winding: flip the fan if it faces away from `n`.
		var face_n: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0])
		if face_n.dot(n) < 0.0:
			pts.reverse()
		# Planar UVs projected along the dominant normal axis.
		var u_axis := Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD
		var t: Vector3 = (u_axis - n * u_axis.dot(n)).normalized()
		var bt := n.cross(t)
		var base := verts.size()
		for p: Vector3 in pts:
			verts.append(p)
			normals.append(n)
			tangents.append_array([t.x, t.y, t.z, 1.0])
			uvs.append(Vector2(t.dot(p) + 0.5, bt.dot(p) + 0.5))
		for i in range(1, pts.size() - 1):
			indices.append_array([base, base + i, base + i + 1])

	var S := [-1.0, 1.0]
	for s in S:
		# Three box faces per sign (+X/-X, +Y/-Y, +Z/-Z), inset by the bevel.
		add_poly.call([px[Vector3(s, -1, -1)], px[Vector3(s, 1, -1)], px[Vector3(s, 1, 1)], px[Vector3(s, -1, 1)]], Vector3(s, 0, 0))
		add_poly.call([py[Vector3(-1, s, -1)], py[Vector3(1, s, -1)], py[Vector3(1, s, 1)], py[Vector3(-1, s, 1)]], Vector3(0, s, 0))
		add_poly.call([pz[Vector3(-1, -1, s)], pz[Vector3(1, -1, s)], pz[Vector3(1, 1, s)], pz[Vector3(-1, 1, s)]], Vector3(0, 0, s))
	for sa in S:
		for sb in S:
			# Twelve edge chamfers, four around each axis.
			add_poly.call([px[Vector3(sa, sb, -1)], py[Vector3(sa, sb, -1)], py[Vector3(sa, sb, 1)], px[Vector3(sa, sb, 1)]], Vector3(sa, sb, 0))
			add_poly.call([px[Vector3(sa, -1, sb)], pz[Vector3(sa, -1, sb)], pz[Vector3(sa, 1, sb)], px[Vector3(sa, 1, sb)]], Vector3(sa, 0, sb))
			add_poly.call([py[Vector3(-1, sa, sb)], pz[Vector3(-1, sa, sb)], pz[Vector3(1, sa, sb)], py[Vector3(1, sa, sb)]], Vector3(0, sa, sb))
	for sx in S:
		for sy in S:
			for sz in S:
				# Eight corner triangles closing the chamfers.
				var k := Vector3(sx, sy, sz)
				add_poly.call([px[k], py[k], pz[k]], k)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
