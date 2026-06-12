# Dev probe: prints the merged mesh AABB of each Kenney blaster GLB so we can
# pick per-weapon scale/orientation. Run:
#   godot --headless --path . --script tools/probe_blasters.gd
extends SceneTree

func _init() -> void:
	for c in "abcdefghijklmnopqr":
		var path := "res://assets/models/weapons/blaster-%s.glb" % c
		var ps: PackedScene = load(path)
		if ps == null:
			print(c, ": LOAD FAILED")
			continue
		var root := ps.instantiate()
		var merged := AABB()
		var first := true
		var stack: Array = [root]
		while stack.size() > 0:
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			if n is MeshInstance3D and n.mesh:
				var xf: Transform3D = _global_xf(n, root)
				var ab: AABB = xf * n.mesh.get_aabb()
				merged = ab if first else merged.merge(ab)
				first = false
		print("%s size=%.2v pos=%.2v end=%.2v" % [c, merged.size, merged.position, merged.end])
		root.free()
	quit()

func _global_xf(n: Node3D, stop: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != stop and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
