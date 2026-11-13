extends Node3D
## Gate: every pickup a built level holds (def supplies, guns, tower-top
## rewards, honeypots) against geometry, air, lava and the navmesh (#528).
## Prints one BAD line per pickup that is inside something solid, has nothing
## within 1 m under it, lies in a lava bed, is more than 1.2 m off the navmesh,
## or has no navmesh route from the spawn.
## The navmesh follows no lift, jump or grapple, so the two navmesh faults alone
## are excused for a pickup that tests/pickup_route_probe walks the real player
## to: its SPOTS table is the one list, read here. Anything else fails: a pickup
## in geometry, in the air or in lava (walked or not), a navmesh fault with no
## walked route, and a SPOTS entry no pickup stands on any more (a stale route).
## A new pickup up a tower or lift belongs in that probe's SPOTS with its route.
## tests/task_reach_probe gates def supplies and guns against their authored
## spot; this also sees what the builder places (grok's tower medkit sat inside
## a scanner mast until #499). 72 s for 26 levels.
##   godot --headless --path . --audio-driver Dummy res://tests/pickup_reach_sweep.tscn [-- levels=gpt,range] [-- list]

const LevelIds := preload("res://tests/level_ids.gd")
const Routes := preload("res://tests/pickup_route_probe.gd")
## A SPOTS entry names its pickup to 0.1 m.
const SPOT_MATCH := 0.3

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, "" if cond else detail])
	if not cond:
		ok = false

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

## What is wrong with a pickup at `p`: [solid faults, navmesh faults]. A solid
## fault (in geometry, in the air, in lava) is never excused.
func _faults(p: Vector3, def: Dictionary, spawn: Vector3, with_nav: bool = true) -> Array:
	var space := get_world_3d().direct_space_state
	var map := get_world_3d().navigation_map
	var solid: Array = []
	var nav: Array = []
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
		solid.append("buried in %s (%s at %s, parent %s)" % [c.name, sz, (c as Node3D).global_position.snapped(Vector3.ONE * 0.1), c.get_parent().name])
	var rq := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p - Vector3.UP * 3.0, 1)
	var rh := space.intersect_ray(rq)
	if rh.is_empty():
		solid.append("nothing under it")
	elif p.y - rh.position.y > 1.0:
		solid.append("floats %.1f m over %s" % [p.y - rh.position.y, rh.collider.name])
	for l: Dictionary in def.get("lava", []):
		var lp: Vector3 = l["pos"]
		var lh: Vector2 = (l["size"] as Vector2) * 0.5
		if absf(p.x - lp.x) < lh.x and absf(p.z - lp.z) < lh.y and p.y < 1.0:
			solid.append("in lava")
	if not with_nav:
		return [solid, nav]
	var cp := NavigationServer3D.map_get_closest_point(map, p)
	var off := Vector2(cp.x - p.x, cp.z - p.z).length()
	if off > 1.2 or absf(cp.y - p.y) > 1.5:
		nav.append("off nav %.1f m (dy %.1f)" % [off, cp.y - p.y])
	else:
		var path := NavigationServer3D.map_get_path(map, spawn, cp, true)
		if path.is_empty() or path[path.size() - 1].distance_to(cp) > 1.5:
			nav.append("no path from spawn (ends %.1f m short at %s)" % [path[path.size() - 1].distance_to(cp) if not path.is_empty() else -1.0, path[path.size() - 1].snapped(Vector3.ONE * 0.1) if not path.is_empty() else Vector3.ZERO])
	return [solid, nav]

func _solid(p: Vector3, def: Dictionary = {}) -> String:
	return "; ".join(_faults(p, def, Vector3.ZERO, false)[0])

## The measure itself, on a floor with one box on it, before any level is built
## (and freed again: a leftover body would sit in every level after it).
func _self_check() -> void:
	var rig := Node3D.new()
	add_child(rig)
	for spec in [[Vector3(0, -0.25, 0), Vector3(20, 0.5, 20)], [Vector3(4, 1.0, 0), Vector3(2, 2, 2)]]:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[1]
		cs.shape = box
		body.add_child(cs)
		body.position = spec[0]
		rig.add_child(body)
	for i in 3:
		await get_tree().physics_frame
	var lava := {"lava": [{"pos": Vector3(-6, 0, 0), "size": Vector2(4, 4)}]}
	_check("self-check: a pickup on open floor has no solid fault", _solid(Vector3(0, 0.3, 0)) == "", _solid(Vector3(0, 0.3, 0)))
	_check("self-check: a pickup inside a box is buried", "buried" in _solid(Vector3(4, 0.3, 0)))
	_check("self-check: a pickup 2 m up floats", "floats" in _solid(Vector3(0, 2.3, 0)))
	_check("self-check: a pickup past the edge of the floor has nothing under it", "nothing under" in _solid(Vector3(30, 0.3, 0)))
	_check("self-check: a pickup in a lava bed is in lava", "in lava" in _solid(Vector3(-6, 0.3, 0), lava))
	rig.queue_free()
	for i in 3:
		await get_tree().physics_frame

func _run() -> void:
	var ids: Array = LevelIds.all()
	var list := false ## `-- list`: one PICK line per pickup seen
	for a in OS.get_cmdline_user_args():
		if a.begins_with("levels="):
			ids = a.trim_prefix("levels=").split(",")
		if a == "list":
			list = true
	await _self_check()
	var total := 0
	var bad := 0
	var walked := 0
	for id: String in ids:
		seed(hash(id))
		var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
		add_child(lvl)
		for i in 90:
			_robots_off()
			await get_tree().physics_frame
		var def := LevelDefs.get_def(id)
		var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
		var pl := get_tree().get_first_node_in_group("player") as Node3D
		if pl:
			spawn = pl.global_position
		var spot: Dictionary = Routes.SPOTS.get(id, {})
		var spot_seen := spot.is_empty()
		var n := 0
		for node in lvl.find_children("*", "Node3D", true, false):
			var f := String(node.scene_file_path)
			if not f.begins_with("res://scenes/pickups/"):
				continue
			n += 1
			var p: Vector3 = (node as Node3D).global_position
			if list:
				print("PICK %s %s %s" % [id, f.get_file().get_basename(), p.snapped(Vector3.ONE * 0.1)])
			var faults := _faults(p, def, spawn)
			var solid: Array = faults[0]
			var nav: Array = faults[1]
			var is_spot: bool = not spot.is_empty() and p.distance_to(spot["at"]) <= SPOT_MATCH
			if is_spot:
				spot_seen = true
			if solid.is_empty() and nav.is_empty():
				continue
			var tag := "%s %s %s: %s" % [id, f.get_file().get_basename(), p.snapped(Vector3.ONE * 0.1), "; ".join(solid + nav)]
			if solid.is_empty() and is_spot:
				walked += 1
				print("WALKED %s (route \"%s\" in pickup_route_probe)" % [tag, spot["route"]])
			else:
				bad += 1
				print("BAD %s" % tag)
		if not spot.is_empty():
			_check("%s: the spot pickup_route_probe walks to, %s, is still a pickup" % [id, spot["at"]], spot_seen, "(route \"%s\" leads to nothing: fix or remove its SPOTS entry)" % spot["route"])
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
	print("TOTAL %d pickups, %d bad, %d off the navmesh but walked by pickup_route_probe" % [total, bad, walked])
	_check("no pickup is in geometry, in the air, in lava, or cut off with no walked route", bad == 0, "(%d BAD above)" % bad)
	_check("the sweep saw pickups", total > 0)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
