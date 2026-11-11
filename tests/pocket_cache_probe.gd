extends Node3D
## Probe: POCKET CACHES (#507). LevelDefs.gate_span opened dead-end pockets
## behind the crossing route gates of 14 levels, and nothing was authored for
## that floor. LevelDefs.get_def now gives every pocket (gate_pockets) a
## supply, two crates and a floor strip, marked "pocket": true.
##   - on a small def: two crossing gates make one pocket, in the quadrant
##     neither gap opens into; a gate with "through" makes none;
##     "pocket_caches": false opts a def out;
##   - asking for a def twice does not double its caches;
##   - a level without gates gets none;
##   - every level with gates has at least one cache; each cache's supply lies
##     inside a pocket, at least 3 m from the spawn and the exit, with its two
##     crates and its strip;
##   - pockets differ (pocket_plan): a pocket of 400 m2 or more, on a level
##     after grok (which introduces sentries), is GUARDED: both supplies and a
##     sentry turret; the second pocket of a level after mistral (which
##     introduces honeypots) is BAITED: a honeypot stands in for the supply;
##     the rest are plain caches. Neither mechanic appears before the level
##     that introduces it, and the campaign has some of each;
##   - nothing a pocket adds (crate, sentry, honeypot, supply) stands within
##     1.5 m of an authored prop, wall block or lore terminal;
##   - built: each cache's pickup stands where the def says, and a navmesh
##     route from the spawn reaches it (tests/task_reach_probe gates its
##     clearance and footing with every other supply).
##   godot --headless --path . --audio-driver Dummy res://tests/pocket_cache_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _defs_call(method: String, args: Array) -> Variant:
	var sc: Script = load("res://scripts/levels/level_defs.gd")
	for m: Dictionary in sc.get_script_method_list():
		if m["name"] == method:
			return sc.callv(method, args)
	return null

func _marked(def: Dictionary, key: String) -> Array:
	return (def.get(key, []) as Array).filter(func(e: Dictionary) -> bool: return e.get("pocket", false))

func _run() -> void:
	# 1. The geometry, on a small def: a z gate at -20 (gap at x 10) and an x
	# gate at 20 (gap at z 15) on a 60 x 80 floor seal x > 20, z < -20.
	var d := {"floor_size": Vector2(60, 80), "gates": [
		{"axis": "z", "at": -20.0, "gap": 8.0, "gap_pos": 10.0},
		{"axis": "x", "at": 20.0, "gap": 8.0, "gap_pos": 15.0},
	]}
	var pockets: Variant = _defs_call("gate_pockets", [d])
	var one: bool = pockets is Array and (pockets as Array).size() == 1
	_check("two crossing gates make one pocket", one, str(pockets))
	if one:
		var r: Rect2 = pockets[0]
		_check("in the quadrant neither gap opens into", r.position.x >= 20.0 and r.end.x <= 30.0 and r.position.y >= -40.0 and r.end.y <= -20.0 and r.get_area() > 60.0, str(r))
	d["gates"][1]["through"] = true
	pockets = _defs_call("gate_pockets", [d])
	_check("a gate with \"through\" makes none", pockets is Array and (pockets as Array).is_empty(), str(pockets))
	d["gates"][1].erase("through")
	var with: Variant = _defs_call("_with_pocket_caches", [d])
	_check("the def gains one supply, two crates and a strip", with is Dictionary and _marked(with, "pickups").size() == 1 and _marked(with, "props").size() == 2 and _marked(with, "accents").size() == 1)
	d["pocket_caches"] = false
	with = _defs_call("_with_pocket_caches", [d])
	_check("\"pocket_caches\": false opts a def out", with is Dictionary and _marked(with, "pickups").is_empty())

	# 1b. Kinds. The same synthetic pockets, as if on levels around the two
	# introductions: 600 m2 and 2 pockets with a second gate pair.
	var big := {"floor_size": Vector2(120, 120), "gates": [
		{"axis": "z", "at": -30.0, "gap": 8.0, "gap_pos": 10.0},
		{"axis": "x", "at": 30.0, "gap": 8.0, "gap_pos": 15.0},
	]}
	var plan: Variant = _defs_call("pocket_plan", [big, "titan"])
	_check("a 400 m2 pocket after grok is guarded", plan is Array and plan == ["guard"], str(plan))
	plan = _defs_call("pocket_plan", [big, "gemini"])
	_check("the same pocket before grok is a plain cache", plan is Array and plan == ["cache"], str(plan))
	plan = _defs_call("pocket_plan", [big, ""])
	_check("and so is one on a level outside the campaign", plan is Array and plan == ["cache"], str(plan))
	var g: Variant = _defs_call("_with_pocket_caches", [big, "titan"])
	_check("a guarded pocket holds both supplies and one sentry", g is Dictionary and _marked(g, "pickups").size() == 2 and _marked(g, "turrets").size() == 1
			and _marked(g, "props").size() == 2 and _marked(g, "accents").size() == 1,
			"%d supplies %d turrets" % [_marked(g, "pickups").size() if g is Dictionary else -1, _marked(g, "turrets").size() if g is Dictionary else -1])
	if g is Dictionary and _marked(g, "turrets").size() == 1 and _marked(g, "pickups").size() == 2:
		var tp: Vector3 = _marked(g, "turrets")[0]["pos"]
		var near := 99.0
		for e: Dictionary in _marked(g, "pickups") + _marked(g, "props"):
			near = minf(near, Vector2(tp.x - e["pos"].x, tp.z - e["pos"].z).length())
		_check("the sentry stands clear of the supplies and crates, within reach of them", near >= 2.0 and near <= 6.0, "%.1f m" % near)

	# 2. The real defs.
	var a := LevelDefs.get_def("mistral")
	var b := LevelDefs.get_def("mistral")
	_check("asking for a def twice does not double its caches", _marked(a, "pickups").size() == 1 and _marked(b, "pickups").size() == 1, "%d then %d" % [_marked(a, "pickups").size(), _marked(b, "pickups").size()])
	_check("a level without gates gets none", _marked(LevelDefs.get_def("gpt"), "pickups").is_empty() and _marked(LevelDefs.get_def("hivemind"), "pickups").is_empty())

	var ids: Array = []
	for path: String in GameState.CAMPAIGN:
		ids.append(path.get_file().trim_suffix(".tscn").trim_prefix("level_"))
	var levels := 0
	var caches := 0
	var tally := {}
	var order: Array = ids
	for id: String in ids:
		var def := LevelDefs.get_def(id)
		if (def.get("gates", []) as Array).is_empty():
			continue
		levels += 1
		var sup := _marked(def, "pickups")
		var rects: Variant = _defs_call("gate_pockets", [def])
		var bad := ""
		var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
		var exit_at: Vector3 = def.get("exit", Vector3.ZERO)
		for s: Dictionary in sup:
			var p: Vector3 = s["pos"]
			var inside := false
			if rects is Array:
				for r: Rect2 in rects:
					if r.has_point(Vector2(p.x, p.z)):
						inside = true
			if not inside:
				bad = "%s outside every pocket" % p.snapped(Vector3.ONE * 0.1)
			if Vector2(p.x - spawn.x, p.z - spawn.z).length() < 3.0 or Vector2(p.x - exit_at.x, p.z - exit_at.z).length() < 3.0:
				bad = "%s on the spawn or the exit" % p.snapped(Vector3.ONE * 0.1)
		var n_pockets := (rects as Array).size() if rects is Array else 0
		var kinds_v: Variant = _defs_call("pocket_plan", [def, id])
		var kinds: Array = kinds_v if kinds_v is Array else []
		var want_sup := kinds.count("cache") + 2 * kinds.count("guard")
		for k: String in kinds:
			tally[k] = int(tally.get(k, 0)) + 1
		if kinds.has("bait") and order.find(id) <= order.find("mistral"):
			bad = "a honeypot before mistral introduces them"
		if kinds.has("guard") and order.find(id) <= order.find("grok"):
			bad = "a sentry before grok introduces them"
		for hp: Dictionary in _marked(def, "honeypots") + _marked(def, "turrets"):
			var hpos: Vector3 = hp["pos"]
			var hin := false
			if rects is Array:
				for r: Rect2 in rects:
					if r.has_point(Vector2(hpos.x, hpos.z)):
						hin = true
			if not hin:
				bad = "%s outside every pocket" % hpos.snapped(Vector3.ONE * 0.1)
		var clash := ""
		for key: String in ["props", "turrets", "honeypots", "pickups"]:
			for mine: Dictionary in _marked(def, key):
				var mp: Vector3 = mine["pos"]
				for akey: String in ["props", "walls", "lore", "turrets", "honeypots"]:
					for theirs: Dictionary in def.get(akey, []):
						if theirs.get("pocket", false) or not (theirs.get("pos") is Vector3):
							continue
						var tp: Vector3 = theirs["pos"]
						var sz: Vector3 = theirs.get("size", Vector3.ZERO)
						if absf(tp.x - mp.x) < sz.x * 0.5 + 1.5 and absf(tp.z - mp.z) < sz.z * 0.5 + 1.5:
							clash = "%s at %s on %s at %s" % [key, mp.snapped(Vector3.ONE * 0.1), akey, tp.snapped(Vector3.ONE * 0.1)]
		_check("%s: nothing a pocket adds stands on authored content" % id, clash == "", clash)
		_check("%s: its caches lie in its pockets, with crates and strips" % id,
				n_pockets >= 1 and kinds.size() == n_pockets and bad == "" and sup.size() == want_sup
				and _marked(def, "honeypots").size() == kinds.count("bait") and _marked(def, "turrets").size() == kinds.count("guard")
				and _marked(def, "props").size() == n_pockets * 2 and _marked(def, "accents").size() == n_pockets,
				"%d pockets %s: %d supplies, %d honeypots, %d sentries %s" % [n_pockets, str(kinds), sup.size(), _marked(def, "honeypots").size(), _marked(def, "turrets").size(), bad])
		if sup.is_empty():
			continue
		# Built.
		seed(hash(id))
		var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
		add_child(lvl)
		for i in 90:
			await get_tree().physics_frame
		var map := get_world_3d().navigation_map
		var from := spawn
		var pl := get_tree().get_first_node_in_group("player") as Node3D
		if pl:
			from = pl.global_position
		var picks: Array = lvl.find_children("*", "Node3D", true, false).filter(func(n: Node) -> bool: return String(n.scene_file_path).begins_with("res://scenes/pickups/"))
		var missing := ""
		var cut := ""
		for s: Dictionary in sup:
			var p: Vector3 = s["pos"]
			caches += 1
			var there := false
			for n: Node3D in picks:
				if n.global_position.distance_to(p) < 0.6:
					there = true
			if not there:
				missing = str(p.snapped(Vector3.ONE * 0.1))
			var cp := NavigationServer3D.map_get_closest_point(map, p)
			var path := NavigationServer3D.map_get_path(map, from, cp, true)
			if cp.distance_to(p) > 1.6 or path.is_empty() or path[path.size() - 1].distance_to(cp) > 1.5:
				cut = str(p.snapped(Vector3.ONE * 0.1))
		_check("%s: each cache's pickup is built and a route from the spawn reaches it" % id, missing == "" and cut == "", "missing %s, cut off %s" % [missing, cut])
		# Report only (#507): can the exit or the spawn be seen from the cache?
		var space := get_world_3d().direct_space_state
		for s: Dictionary in sup:
			var eye: Vector3 = s["pos"] + Vector3.UP * 1.5
			var sees := []
			for target: Array in [["exit", exit_at], ["spawn", spawn]]:
				var q := PhysicsRayQueryParameters3D.create(eye, (target[1] as Vector3) * Vector3(1, 0, 1) + Vector3.UP * 1.5, 1)
				if space.intersect_ray(q).is_empty():
					sees.append("%s at %d m" % [target[0], int(eye.distance_to(target[1]))])
			print("SIGHT %s cache %s sees: %s" % [id, (s["pos"] as Vector3).snapped(Vector3.ONE * 0.1), ", ".join(sees) if not sees.is_empty() else "neither exit nor spawn"])
		lvl.queue_free()
		# Robots are parented beside the level and outlive it (tests/README.md).
		for e in get_tree().get_nodes_in_group("enemy"):
			e.queue_free()
		for i in 5:
			await get_tree().physics_frame
	_check("levels with gates checked", levels >= 14 and caches >= 14, "%d levels, %d caches" % [levels, caches])
	_check("the campaign's pockets are not all alike", int(tally.get("cache", 0)) >= 4 and int(tally.get("bait", 0)) >= 3 and int(tally.get("guard", 0)) >= 4, str(tally))

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
