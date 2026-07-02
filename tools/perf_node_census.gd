extends Node
## Counts VisualInstance3D nodes in a built level, grouped by their nearest
## named ancestor container (level_builder groups decorative passes under
## named parents like "FacilityDetail"/"OutdoorDetail"/"CoverTrim" etc.) and by
## mesh resource identity, to find which decorative pass is responsible for
## the 644-node count found in level_gpt.
## Run: godot --headless --path . --quit-after 300 tools/perf_node_census.tscn

const LEVEL_ID := "gpt"

func _ready() -> void:
	var lvl: Node = load("res://scenes/levels/level_%s.tscn" % LEVEL_ID).instantiate()
	add_child(lvl)
	await get_tree().create_timer(20.0).timeout # match the ~18s the windowed perf test's slow warmup takes

	var all := lvl.find_children("*", "VisualInstance3D", true, false)
	print("TOTAL VisualInstance3D: ", all.size())

	var by_parent := {}
	var by_mesh := {}
	var by_material_uniqueness := {"unique_shader_mat": 0, "shared_or_none": 0}
	for n in all:
		var container := _named_ancestor(n)
		by_parent[container] = int(by_parent.get(container, 0)) + 1
		var mesh_id := "no-mesh"
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var m: Mesh = (n as MeshInstance3D).mesh
			mesh_id = "%s#%d" % [m.get_class(), m.get_instance_id() % 100000]
			var mat := (n as MeshInstance3D).get_surface_override_material(0)
			if mat == null and m.get_surface_count() > 0:
				mat = m.surface_get_material(0)
			if mat is ShaderMaterial:
				by_material_uniqueness["unique_shader_mat"] += 1
			else:
				by_material_uniqueness["shared_or_none"] += 1
		by_mesh[mesh_id] = int(by_mesh.get(mesh_id, 0)) + 1

	print("\n--- by nearest named container ---")
	var pkeys := by_parent.keys()
	pkeys.sort_custom(func(a, b): return by_parent[a] > by_parent[b])
	for k in pkeys:
		if by_parent[k] >= 5:
			print("  %-30s %d" % [k, by_parent[k]])

	print("\n--- material uniqueness (ShaderMaterial = can't batch/instance) ---")
	print("  ", by_material_uniqueness)

	print("\n--- top duplicate mesh resources (candidates for MultiMeshInstance3D) ---")
	var mkeys := by_mesh.keys()
	mkeys.sort_custom(func(a, b): return by_mesh[a] > by_mesh[b])
	for i in mini(15, mkeys.size()):
		print("  %-20s x%d" % [mkeys[i], by_mesh[mkeys[i]]])

	print("PERF_NODE_CENSUS_DONE")
	get_tree().quit()

## Walk up from n to lvl, return the name of the node just below a recognizable
## "detail group" container, or the top-level child of lvl if none found.
func _named_ancestor(n: Node) -> String:
	var cur := n
	var path := []
	while cur and cur != get_node("/root"):
		path.append(cur.name)
		cur = cur.get_parent()
	# path[0] is n itself; walk from the root end (level) down a couple levels.
	path.reverse()
	# path[0]=root Node, path[1]=level instance, path[2] = level's direct child
	if path.size() > 2:
		return String(path[2])
	elif path.size() > 1:
		return String(path[1])
	return "?"
