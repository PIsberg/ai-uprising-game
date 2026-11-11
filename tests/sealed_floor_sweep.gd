extends Node3D
## Report-only sweep: ground floor a built level walls off from its spawn.
## Samples the floor every STEP metres; a sample that lies on the ground-level
## navmesh but has no navmesh route from the spawn is "cut off". Neighbouring
## cut-off samples are grouped, and each group of MIN_CELLS or more prints one
## SEALED line with its bounds and area. A group is a lead, not a verdict: the
## navmesh does not follow jumps, lifts, jump pads, ziplines or the grapple, and
## a firewall that opens later still cuts it. tests/sealed_floor_probe is the
## gate for the def-level cause (two crossing "gates").
##   godot --headless --path . --audio-driver Dummy res://tests/sealed_floor_sweep.tscn [-- levels=mistral,gpt]

const LevelIds := preload("res://tests/level_ids.gd")
const STEP := 2.0
const MIN_CELLS := 4 ## 16 m2

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ids: Array = LevelIds.all()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("levels="):
			ids = a.trim_prefix("levels=").split(",")
	var groups := 0
	for id: String in ids:
		seed(hash(id))
		var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
		add_child(lvl)
		for i in 90:
			await get_tree().physics_frame
		var def := LevelDefs.get_def(id)
		var map := get_world_3d().navigation_map
		var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
		var pl := get_tree().get_first_node_in_group("player") as Node3D
		if pl:
			spawn = pl.global_position
		var res := scan(def, map, spawn)
		for g: Dictionary in res["groups"]:
			var lo: Vector2 = g["lo"]
			var hi: Vector2 = g["hi"]
			print("SEALED %s: %d m2, x %.0f..%.0f, z %.0f..%.0f (world metres; authored = / %.1f)" % [id, g["area"], lo.x, hi.x, lo.y, hi.y, LevelDefs.WORLD_SCALE])
		var on_nav: int = res["on_nav"]
		var n: int = (res["groups"] as Array).size()
		var cut_n: int = res["cut"]
		print("LEVEL %s: %d floor samples on the navmesh, %d cut off, %d groups" % [id, on_nav, cut_n, n])
		groups += n
		lvl.queue_free()
		for i in 5:
			await get_tree().physics_frame
	print("TOTAL %d sealed groups" % groups)
	get_tree().quit(0)

## The scan: {"on_nav": ground samples on the navmesh, "cut": how many of them
## have no route from `spawn`, "groups": [{"area": m2, "lo": Vector2, "hi":
## Vector2 (x, z)}] for every group of MIN_CELLS or more}.
static func scan(def: Dictionary, map: RID, spawn: Vector3) -> Dictionary:
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var cut := {} ## Vector2i cell -> true
	var on_nav := 0
	var nx := int(fs.x / STEP)
	var nz := int(fs.y / STEP)
	for ix in nx:
		for iz in nz:
			var p := Vector3(-fs.x * 0.5 + (ix + 0.5) * STEP, 0.0, -fs.y * 0.5 + (iz + 0.5) * STEP)
			var cp := NavigationServer3D.map_get_closest_point(map, p)
			if Vector2(cp.x - p.x, cp.z - p.z).length() > 0.6 or absf(cp.y) > 0.6:
				continue # in a wall, a hazard bed, or under a deck only
			on_nav += 1
			var path := NavigationServer3D.map_get_path(map, spawn, cp, true)
			if path.is_empty() or path[path.size() - 1].distance_to(cp) > 1.5:
				cut[Vector2i(ix, iz)] = true
	# Group the cut-off cells (4-neighbour flood).
	var seen := {}
	var groups: Array = []
	for c: Vector2i in cut:
		if seen.has(c):
			continue
		var todo: Array[Vector2i] = [c]
		seen[c] = true
		var cells: Array[Vector2i] = []
		while not todo.is_empty():
			var k: Vector2i = todo.pop_back()
			cells.append(k)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var m: Vector2i = k + d
				if cut.has(m) and not seen.has(m):
					seen[m] = true
					todo.append(m)
		if cells.size() < MIN_CELLS:
			continue
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for k in cells:
			var x := -fs.x * 0.5 + (k.x + 0.5) * STEP
			var z := -fs.y * 0.5 + (k.y + 0.5) * STEP
			lo = Vector2(minf(lo.x, x), minf(lo.y, z))
			hi = Vector2(maxf(hi.x, x), maxf(hi.y, z))
		groups.append({"area": cells.size() * int(STEP * STEP), "lo": lo, "hi": hi})
	return {"on_nav": on_nav, "cut": cut.size(), "groups": groups}
