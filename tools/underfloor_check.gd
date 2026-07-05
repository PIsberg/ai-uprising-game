extends Node3D
## Loads each level and reports every live enemy whose body or visual bottom
## sits below the local floor (raycast down from above its head). Finds robots
## spawned/settled UNDER the floor. LEVEL ids via UF_LEVELS env (csv), default
## the round-robot levels.
##   godot --headless --path . --quit-after 4000 res://tools/underfloor_check.tscn

func _ready() -> void:
	var ids_env := OS.get_environment("UF_LEVELS")
	var ids := ids_env.split(",", false) if ids_env != "" else \
			PackedStringArray(["frostbreak", "neon", "sublevel", "crucible"])
	for id in ids:
		var lvl: Node = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
		add_child(lvl)
		await get_tree().create_timer(2.5).timeout
		var flagged := 0
		for e in get_tree().get_nodes_in_group("enemy"):
			if not (e is Node3D):
				continue
			var b := e as Node3D
			# Local floor: ray down from 2 m above the enemy head.
			var from: Vector3 = b.global_position + Vector3(0, 4.0, 0)
			var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -30, 0), 1)
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			var floor_y: float = hit["position"].y if hit else -99.0
			var lo := 1e9
			for mi in b.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				if m.mesh:
					lo = minf(lo, (m.global_transform * m.mesh.get_aabb()).position.y)
			# The ray from above hits the floor ABOVE a buried bot — so a body
			# well below that surface, or a visual bottom sunk into it, flags.
			if b.global_position.y < floor_y - 0.4 or (lo < floor_y - 0.45 and lo < 1e8):
				flagged += 1
				print("UNDER %-10s %-12s body_y=%6.2f visual_lo=%6.2f floor_y=%6.2f at %s" % [
					id, b.name, b.global_position.y, lo, floor_y, b.global_position])
		print("UF %-10s enemies=%d flagged=%d" % [id, get_tree().get_nodes_in_group("enemy").size(), flagged])
		lvl.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("UNDERFLOOR_DONE")
	get_tree().quit()
