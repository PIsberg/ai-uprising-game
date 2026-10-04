extends Node
## Builds every campaign level for real and checks that no authored objective
## sits in solid geometry: each positioned task (key, core, console, zone, shard,
## payload, escape ring, HVT spawn) and each weapon pickup must be where the def
## put it after the builder's burial rescue has run, clear of world geometry and
## near the navmesh. The usual culprit is an outdoor light authored over the
## spot: every outdoor light builds a solid mast down to the floor.
##
## The rescue still exists for genuinely buried objectives (level 1 shipped
## one), so "unmoved" is the strict bar: a move means the def authored the task
## into a wall, onto a prop, or into a hero monolith, and the player sees it
## nudged off its set dressing. Controls prove the rescue still fires:
##   - a point inside assembly's hero monolith is moved,
##   - a ring zone centred on that monolith is NOT (the player stands in the ring),
##   - an ObjectiveCore on open floor is NOT (it used to hit its own collider).
##   godot --headless --path . --audio-driver Dummy res://tests/task_reach_probe.tscn

var _ok := true

func _ready() -> void:
	_run.call_deferred()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["ok  " if cond else "BAD ", name, detail])
	if not cond:
		_ok = false

func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

## Builder-side id for a task dict (mirrors LevelBuilder._task_id).
func _tid(lvl: Node, t: Dictionary) -> String:
	return lvl._task_id(t)

## Live task objects of the level, keyed by task id (shards share one id).
func _task_nodes(lvl: Node) -> Dictionary:
	var out := {}
	for c in lvl.get_children():
		if c is Node3D and "task_id" in c:
			var id: String = c.task_id
			if not out.has(id):
				out[id] = []
			out[id].append(c)
	return out

func _run() -> void:
	for path: String in GameState.CAMPAIGN:
		await _check_level(path)
	await _controls()
	print("RESULT ", "PASS" if _ok else "FAIL")
	get_tree().quit()

func _check_level(path: String) -> void:
	var lvl: Node3D = load(path).instantiate()
	get_tree().root.add_child(lvl)
	# Burial rescue runs 1.0 s after a task spawns; give the navmesh bake time too.
	for i in 8:
		await get_tree().create_timer(0.25).timeout
	var def: Dictionary = LevelDefs.get_def(lvl.level_id)
	var live := _task_nodes(lvl)
	var space := lvl.get_world_3d().direct_space_state
	var nav_map := lvl.get_world_3d().navigation_map
	var lid: String = lvl.level_id
	for t: Dictionary in def.get("tasks", []):
		var points: Array = []
		if t.has("pos"):
			points.append(t["pos"])
		for sp in t.get("points", []):
			points.append(sp["pos"] if sp is Dictionary else sp)
		if points.is_empty():
			continue
		var id := _tid(lvl, t)
		var radius: float = t.get("radius", 5.5 if t.get("type", "") == "hold_zone" else 0.0)
		if t.get("type", "") == "escape":
			radius = t.get("radius", 4.0)
		# An assassinate target is a robot that walks (or flies) off its spawn,
		# so its live position says nothing: judge the authored spot instead.
		var hvt: bool = t.get("type", "") == "assassinate"
		var nodes: Array = [] if hvt else live.get(id, [])
		for k in points.size():
			var authored: Vector3 = points[k]
			var where: Vector3
			if k < nodes.size():
				# Spawned: what the builder actually did.
				where = nodes[k].position
			else:
				# Staged (spawns later): what the builder would do now.
				where = lvl._reachable_task_pos(authored, null, radius)
			var moved := _flat(where).distance_to(_flat(authored)) > 0.01
			var own: Array[RID] = lvl._own_bodies(nodes[k]) if k < nodes.size() else ([] as Array[RID])
			var clear: bool = lvl._point_clear(space, where, own) \
				or lvl._ring_clear(space, where, radius * 0.5, own)
			var nav := NavigationServer3D.map_get_closest_point(nav_map, where)
			var nav_d := _flat(nav).distance_to(_flat(where))
			# Zones are judged by their ring, not their centre's navmesh distance;
			# a target is shot, not walked to (water_world's swims over open sea).
			var nav_ok := nav_d <= 1.6 or radius > 0.0 or hvt
			_check("%s %s#%d" % [lid, id, k], not moved and clear and nav_ok,
				"authored=%s at=%s clear=%s nav_d=%.2f" % [authored, where, clear, nav_d])
	# Weapon pickups go through the same rescue (an Area3D, so no self-hit).
	var weapons: Array = def.get("extra_weapons", []).duplicate()
	if def.has("weapon"):
		weapons.push_front(def["weapon"])
	for w: Dictionary in weapons:
		var wp: Vector3 = w["pos"]
		var at: Vector3 = lvl._reachable_task_pos(wp)
		_check("%s weapon %s" % [lid, String(w["scene"]).get_file()],
			_flat(at).distance_to(_flat(wp)) < 0.01, "authored=%s at=%s" % [wp, at])
	lvl.queue_free()
	await get_tree().create_timer(0.3).timeout

func _controls() -> void:
	var lvl: Node3D = load("res://scenes/levels/level_assembly.tscn").instantiate()
	get_tree().root.add_child(lvl)
	for i in 8:
		await get_tree().create_timer(0.25).timeout
	# The hero monolith stands at the origin: a point objective there is buried.
	var p: Vector3 = lvl._reachable_task_pos(Vector3.ZERO)
	_check("control: point in hero monolith is moved", _flat(p).length() > 1.0, str(p))
	# A 5.5 m ring around the same monolith is standable, so it stays put.
	var z: Vector3 = lvl._reachable_task_pos(Vector3.ZERO, null, 5.5)
	_check("control: ring zone around monolith stays", _flat(z).length() < 0.01, str(z))
	# An objective core on open floor must not trip over its own StaticBody.
	var open := Vector3(-14, 0, 14) * LevelDefs.WORLD_SCALE
	var space := lvl.get_world_3d().direct_space_state
	_check("control: open spot is clear without the core", lvl._point_clear(space, open))
	var core := ObjectiveCore.new()
	core.task_id = "probe_core"
	core.position = open
	lvl.add_child(core)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("control: the core itself blocks the spot", not lvl._point_clear(space, open),
		"(precondition: proves the exclusion below is doing the work)")
	var c: Vector3 = lvl._reachable_task_pos(open, core)
	_check("control: core on open floor stays", _flat(c).distance_to(_flat(open)) < 0.01, str(c))
	lvl.queue_free()
	await get_tree().create_timer(0.3).timeout
