extends Node3D
## Probe: no route gate walls floor off (#500). Two full-span "gates" that
## cross sealed the quadrant neither gap opens into: 120 to 870 m2 of lit,
## dressed floor in 14 levels that nobody could walk onto. LevelBuilder.gate_span
## now stops a gate at an earlier gate that crosses it.
##   - gate_span on small defs: the first gate keeps the floor's span; a later
##     gate stops at the earlier one on the far side of its own gap, on either
##     side; it is not stopped by a gate on its own axis, nor where the earlier
##     gate's gap lies on its line; "through" keeps the full span;
##   - every level with gates, built: no group of cut-off ground floor of
##     BIG m2 or more (tests/sealed_floor_sweep's scan; what is left is tower
##     cores and the like, 48 m2 at most);
##   - and the fix opens no way round: the navmesh route from the spawn to the
##     exit still crosses every gate's line inside that gate's gap (or over
##     its top, on an authored sky-bridge).
##   godot --headless --path . --audio-driver Dummy res://tests/sealed_floor_probe.tscn

const LevelIds := preload("res://tests/level_ids.gd")
const Sweep := preload("res://tests/sealed_floor_sweep.gd")
const BIG := 100

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _span(def: Dictionary, i: int) -> Vector2:
	var builder: Script = load("res://scripts/levels/level_builder.gd")
	for m: Dictionary in builder.get_script_method_list():
		if m["name"] == "gate_span":
			return builder.call("gate_span", def, i)
	# The old builder: every gate ran wall to wall.
	var fs: Vector2 = def["floor_size"]
	var g: Dictionary = def["gates"][i]
	var half := (fs.x if String(g.get("axis", "z")) == "z" else fs.y) * 0.5
	return Vector2(-half, half)

func _run() -> void:
	# 1. gate_span.
	var d := {"floor_size": Vector2(60, 80), "gates": [
		{"axis": "z", "at": -20.0, "gap": 8.0, "gap_pos": 10.0},
		{"axis": "x", "at": 20.0, "gap": 8.0, "gap_pos": 15.0},
	]}
	_check("the first gate keeps the floor's span", _span(d, 0) == Vector2(-30, 30), str(_span(d, 0)))
	_check("a later gate stops at the earlier one that crosses it", _span(d, 1) == Vector2(-20, 40), str(_span(d, 1)))
	d["gates"][1]["gap_pos"] = -30.0
	_check("on whichever side of its gap the earlier gate lies", _span(d, 1) == Vector2(-40, -20), str(_span(d, 1)))
	d["gates"][1]["gap_pos"] = 15.0
	d["gates"][1]["through"] = true
	_check("\"through\" keeps the full span", _span(d, 1) == Vector2(-40, 40), str(_span(d, 1)))
	d["gates"][1].erase("through")
	d["gates"][0]["gap_pos"] = 20.0 # the earlier gate's gap is on the later gate's line: it does not stop it
	_check("an earlier gate does not stop a gate that runs through its gap", _span(d, 1) == Vector2(-40, 40), str(_span(d, 1)))
	d["gates"][0]["gap_pos"] = 10.0
	d["gates"].insert(1, {"axis": "x", "at": 0.0, "gap": 6.0, "gap_pos": 0.0})
	_check("a gate on the same axis does not stop it", _span(d, 2) == Vector2(-20, 40), str(_span(d, 2)))
	d["gates"].insert(1, {"axis": "z", "at": 30.0, "gap": 6.0, "gap_pos": -20.0})
	_check("two earlier gates, one each side of the gap: it runs between them", _span(d, 3) == Vector2(-20, 30), str(_span(d, 3)))

	# 2. Every gated level, built.
	var levels := 0
	var ids: Array = []
	for path: String in GameState.CAMPAIGN:
		ids.append(path.get_file().trim_suffix(".tscn").trim_prefix("level_"))
	for id: String in ["range", "horde"]:
		if not ids.has(id):
			ids.append(id)
	for id: String in ids:
		var def := LevelDefs.get_def(id)
		var gates: Array = def.get("gates", [])
		if gates.is_empty():
			continue
		levels += 1
		seed(hash(id))
		var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
		add_child(lvl)
		for i in 90:
			await get_tree().physics_frame
		var map := get_world_3d().navigation_map
		var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
		var pl := get_tree().get_first_node_in_group("player") as Node3D
		if pl:
			spawn = pl.global_position
		var res := Sweep.scan(def, map, spawn)
		var worst := 0
		var where := ""
		for g: Dictionary in res["groups"]:
			if int(g["area"]) > worst:
				worst = int(g["area"])
				where = "x %.0f..%.0f, z %.0f..%.0f" % [g["lo"].x, g["hi"].x, g["lo"].y, g["hi"].y]
		_check("%s: no walled-off floor of %d m2 or more" % [id, BIG], worst < BIG and int(res["on_nav"]) > 200, "largest %d m2 %s, %d samples" % [worst, where, res["on_nav"]])
		# The route to the exit still threads every gap.
		var goal := NavigationServer3D.map_get_closest_point(map, def.get("exit", Vector3.ZERO))
		var path := NavigationServer3D.map_get_path(map, spawn, goal, true)
		var round_it := ""
		var crossed := 0
		for i in range(1, path.size()):
			var a := path[i - 1]
			var b := path[i]
			for g: Dictionary in gates:
				var x_axis := String(g.get("axis", "z")) == "x"
				var at := float(g.get("at", 0.0))
				var a0 := a.x if x_axis else a.z
				var b0 := b.x if x_axis else b.z
				if (a0 - at) * (b0 - at) >= 0.0:
					continue
				var t := (at - a0) / (b0 - a0)
				if lerpf(a.y, b.y, t) > float(g.get("height", 4.5)) - 0.5:
					continue # over the top on a sky-bridge: the high road is authored
				crossed += 1
				var along := lerpf(a.z, b.z, t) if x_axis else lerpf(a.x, b.x, t)
				if absf(along - float(g.get("gap_pos", 0.0))) > float(g.get("gap", 5.5)) * 0.5 + 0.5:
					round_it = "%s gate at %.1f crossed at %.1f, gap at %.1f" % [g.get("axis", "z"), at, along, g.get("gap_pos", 0.0)]
		var reached := not path.is_empty() and path[path.size() - 1].distance_to(goal) < 2.0
		_check("%s: the route to the exit crosses every gate through its gap" % id, reached and round_it == "" and crossed >= 1, "%d crossings on the ground %s" % [crossed, round_it])
		LevelIds.unload(lvl)
		for i in 5:
			await get_tree().physics_frame
	_check("levels with gates checked", levels >= 14, str(levels))

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
