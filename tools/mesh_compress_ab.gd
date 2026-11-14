extends SceneTree
## A/B for tools/import/mesh_compress.gd (#56): what does storing a surface
## compressed cost in accuracy? Loads each model, keeps its arrays, rebuilds the
## uncompressed static surfaces compressed in the same process and compares what
## the mesh then decodes to: position error (mm and as a share of the model's
## size), normal and tangent angle, UV error in texels of a 1024 px sheet, and
## whether the indices and LODs are identical.
##   godot --headless --path . --script res://tools/mesh_compress_ab.gd -- [res://a.glb ...]
## With no arguments it takes every model under assets/. Run it on a model
## imported WITHOUT the post-import script: once imported with it there is
## nothing left to rebuild and the row says so.

const MeshCompress := preload("res://tools/import/mesh_compress.gd")

func _walk(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() in ["glb", "gltf", "fbx"]:
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_walk(dir + "/" + d, out)

func _bytes(mesh: ArrayMesh) -> int:
	var b := 0
	for s in mesh.get_surface_count():
		var d: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), s)
		b += (d["vertex_data"] as PackedByteArray).size() + (d.get("attribute_data", PackedByteArray()) as PackedByteArray).size()
	return b

func _init() -> void:
	var files: Array = []
	for a in OS.get_cmdline_user_args():
		files.append(a)
	if files.is_empty():
		_walk("res://assets", files)
	var tot_before := 0
	var tot_after := 0
	var tot_verts := 0
	var w_pos := 0.0
	var w_rel := 0.0
	var w_nrm := 0.0
	var w_tan := 0.0
	var w_uv := 0.0
	var all_same := true
	for path: String in files:
		var ps := load(path) as PackedScene
		if ps == null:
			continue
		var root: Node = ps.instantiate()
		var census := MeshCompress.census(root)
		if census[0] == 0:
			root.free()
			continue
		var before := 0
		var after := 0
		var e_pos := 0.0
		var e_rel := 0.0
		var e_nrm := 0.0
		var e_tan := 0.0
		var e_uv := 0.0
		var moved_tan := 0
		var same := true
		for mesh in MeshCompress.meshes(root):
			var old: Array = []
			for s in mesh.get_surface_count():
				var d: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), s)
				old.append({"arrays": mesh.surface_get_arrays(s), "lods": d.get("lods", []), "take": MeshCompress.wants(mesh, int(d["format"]), int(d["vertex_count"])),
					"mat": mesh.surface_get_material(s), "name": mesh.surface_get_name(s)})
			var b0 := _bytes(mesh)
			if MeshCompress.compress_mesh(mesh) == 0:
				continue
			before += b0
			after += _bytes(mesh)
			for s in mesh.get_surface_count():
				var o: Dictionary = old[s]
				var d2: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), s)
				var now: Array = mesh.surface_get_arrays(s)
				same = same and now[Mesh.ARRAY_INDEX] == o["arrays"][Mesh.ARRAY_INDEX] \
					and mesh.surface_get_material(s) == o["mat"] and mesh.surface_get_name(s) == o["name"]
				var l0: Array = o["lods"]
				var l1: Array = d2.get("lods", [])
				same = same and l0.size() == l1.size()
				for k in mini(l0.size(), l1.size()):
					same = same and l0[k]["index_data"] == l1[k]["index_data"] and is_equal_approx(l0[k]["edge_length"], l1[k]["edge_length"])
				if not o["take"]:
					continue
				var p0: PackedVector3Array = o["arrays"][Mesh.ARRAY_VERTEX]
				var p1: PackedVector3Array = now[Mesh.ARRAY_VERTEX]
				var n0: PackedVector3Array = o["arrays"][Mesh.ARRAY_NORMAL]
				var n1: PackedVector3Array = now[Mesh.ARRAY_NORMAL]
				same = same and p0.size() == p1.size()
				var size := mesh.get_aabb().size.length()
				var worst_here := 0.0 # this surface's own, against this mesh's own size
				for i in mini(p0.size(), p1.size()):
					worst_here = maxf(worst_here, p0[i].distance_to(p1[i]))
					e_nrm = maxf(e_nrm, n0[i].normalized().angle_to(n1[i].normalized()))
				e_pos = maxf(e_pos, worst_here)
				e_rel = maxf(e_rel, worst_here / maxf(size, 0.0001))
				if o["arrays"][Mesh.ARRAY_TANGENT] != null and now[Mesh.ARRAY_TANGENT] != null:
					var t0: PackedFloat32Array = o["arrays"][Mesh.ARRAY_TANGENT]
					var t1: PackedFloat32Array = now[Mesh.ARRAY_TANGENT]
					for i in mini(n0.size(), t1.size() / 4):
						var a := Vector3(t0[i * 4], t0[i * 4 + 1], t0[i * 4 + 2])
						var b := Vector3(t1[i * 4], t1[i * 4 + 1], t1[i * 4 + 2])
						same = same and signf(t0[i * 4 + 3]) == signf(t1[i * 4 + 3])
						# A tangent the importer's own check rejected is expected to move.
						if absf(a.dot(n0[i])) > 0.0001:
							moved_tan += 1
						elif a.length_squared() > 0.0 and b.length_squared() > 0.0:
							e_tan = maxf(e_tan, a.angle_to(b))
				if o["arrays"][Mesh.ARRAY_TEX_UV] != null:
					var u0: PackedVector2Array = o["arrays"][Mesh.ARRAY_TEX_UV]
					var u1: PackedVector2Array = now[Mesh.ARRAY_TEX_UV]
					for i in mini(u0.size(), u1.size()):
						e_uv = maxf(e_uv, (u0[i] - u1[i]).abs().dot(Vector2.ONE) * 0.5 * 1024.0)
		print("AB %-34s %7d of %7d verts  %5.2f -> %5.2f MB  pos %.3f mm (%.5f %% of size)  normal %.3f deg  tangent %.3f deg (%d squared)  uv %.3f texel  indices/LODs/materials %s" % [
			path.get_file(), census[0], census[1], before / 1048576.0, after / 1048576.0, e_pos * 1000.0, e_rel * 100.0,
			rad_to_deg(e_nrm), rad_to_deg(e_tan), moved_tan, e_uv, "same" if same else "DIFFER"])
		tot_before += before
		tot_after += after
		tot_verts += census[0]
		w_pos = maxf(w_pos, e_pos)
		w_rel = maxf(w_rel, e_rel)
		w_nrm = maxf(w_nrm, e_nrm)
		w_tan = maxf(w_tan, e_tan)
		w_uv = maxf(w_uv, e_uv)
		all_same = all_same and same
		root.free()
	print("AB TOTAL %d verts  %.2f -> %.2f MB of vertex data  worst: pos %.3f mm (%.5f %% of size), normal %.3f deg, tangent %.3f deg, uv %.3f texel  indices/LODs/materials %s" % [
		tot_verts, tot_before / 1048576.0, tot_after / 1048576.0, w_pos * 1000.0, w_rel * 100.0, rad_to_deg(w_nrm), rad_to_deg(w_tan), w_uv, "same" if all_same else "DIFFER"])
	quit()
