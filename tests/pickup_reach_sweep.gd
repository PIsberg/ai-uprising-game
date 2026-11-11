extends Node3D
## Report-only sweep: every pickup a built level holds (def supplies, guns,
## tower-top rewards, honeypots) against geometry, air, lava and the navmesh.
## Prints one BAD line per pickup that is inside something solid, has nothing
## within 1 m under it, lies in a lava bed, is more than 1.2 m off the navmesh,
## or has no navmesh route from the spawn. That last one is only a lead for a
## pickup up a tower, a lift or a jump: the navmesh does not follow those. The
## six it flags today are walked by the real player in tests/pickup_route_probe
## (suite); a new one belongs in that probe's SPOTS with its route.
## tests/task_reach_probe is the gate for def supplies and guns; this also sees
## what the builder places (grok's tower medkit has a light mast through it).
##   godot --headless --path . --audio-driver Dummy res://tests/pickup_reach_sweep.tscn [-- levels=gpt,range]

const LevelIds := preload("res://tests/level_ids.gd")

func _ready() -> void:
	_run.call_deferred()

## Robots do nothing while a level is measured. A VACUUM eats the supplies in
## its reach, and a robot outlives its level here (see the teardown): by titan
## three were loose and 2 to 7 pickups a run went uncounted, a different set
## each run, so those were never checked (#514).
func _robots_off() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.process_mode != Node.PROCESS_MODE_DISABLED:
			e.process_mode = Node.PROCESS_MODE_DISABLED

func _run() -> void:
	var ids: Array = LevelIds.all()
	var list := false ## `-- list`: one PICK line per pickup seen
	for a in OS.get_cmdline_user_args():
		if a.begins_with("levels="):
			ids = a.trim_prefix("levels=").split(",")
		if a == "list":
			list = true
	var total := 0
	var bad := 0
	for id: String in ids:
		seed(hash(id))
		var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
		add_child(lvl)
		for i in 90:
			_robots_off()
			await get_tree().physics_frame
		var def := LevelDefs.get_def(id)
		var space := get_world_3d().direct_space_state
		var map := get_world_3d().navigation_map
		var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
		var pl := get_tree().get_first_node_in_group("player") as Node3D
		if pl:
			spawn = pl.global_position
		var n := 0
		for node in lvl.find_children("*", "Node3D", true, false):
			var f := String(node.scene_file_path)
			if not f.begins_with("res://scenes/pickups/"):
				continue
			n += 1
			var p: Vector3 = (node as Node3D).global_position
			if list:
				print("PICK %s %s %s" % [id, f.get_file().get_basename(), p.snapped(Vector3.ONE * 0.1)])
			var why: Array = []
			var sh := SphereShape3D.new()
			sh.radius = 0.2
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = sh
			q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.45)
			q.collision_mask = 1
			var hits := space.intersect_shape(q, 4)
			if not hits.is_empty():
				var c: Node = hits[0].collider
				var sz := ""
				for ch in c.get_children():
					if ch is CollisionShape3D and ch.shape is BoxShape3D:
						sz = "box %s" % (ch.shape as BoxShape3D).size.snapped(Vector3.ONE * 0.1)
					elif ch is CollisionShape3D and ch.shape:
						sz = ch.shape.get_class()
				why.append("buried in %s (%s at %s, parent %s)" % [c.name, sz, (c as Node3D).global_position.snapped(Vector3.ONE * 0.1), c.get_parent().name])
			var rq := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p - Vector3.UP * 3.0, 1)
			var rh := space.intersect_ray(rq)
			if rh.is_empty():
				why.append("nothing under it")
			elif p.y - rh.position.y > 1.0:
				why.append("floats %.1f m over %s" % [p.y - rh.position.y, rh.collider.name])
			for l: Dictionary in def.get("lava", []):
				var lp: Vector3 = l["pos"]
				var lh: Vector2 = (l["size"] as Vector2) * 0.5
				if absf(p.x - lp.x) < lh.x and absf(p.z - lp.z) < lh.y and p.y < 1.0:
					why.append("in lava")
			var cp := NavigationServer3D.map_get_closest_point(map, p)
			var off := Vector2(cp.x - p.x, cp.z - p.z).length()
			if off > 1.2 or absf(cp.y - p.y) > 1.5:
				why.append("off nav %.1f m (dy %.1f)" % [off, cp.y - p.y])
			else:
				var path := NavigationServer3D.map_get_path(map, spawn, cp, true)
				if path.is_empty() or path[path.size() - 1].distance_to(cp) > 1.5:
					why.append("no path from spawn (ends %.1f m short at %s)" % [path[path.size() - 1].distance_to(cp) if not path.is_empty() else -1.0, path[path.size() - 1].snapped(Vector3.ONE * 0.1) if not path.is_empty() else Vector3.ZERO])
			if not why.is_empty():
				bad += 1
				print("BAD %s %s %s: %s" % [id, f.get_file().get_basename(), p.snapped(Vector3.ONE * 0.1), "; ".join(why)])
		print("LEVEL %s: %d pickups" % [id, n])
		total += n
		lvl.queue_free()
		# Spawned robots are parented beside the level, not under it, so freeing
		# the level leaves them in the tree for every level after it.
		for e in get_tree().get_nodes_in_group("enemy"):
			if not lvl.is_ancestor_of(e):
				e.queue_free()
		for i in 5:
			await get_tree().physics_frame
	print("TOTAL %d pickups, %d flagged" % [total, bad])
	get_tree().quit(0)
