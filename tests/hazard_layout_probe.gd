extends Node3D
## The two sea levels (lava_world, water_world) are the campaign's only arenas
## where the WHOLE floor is a hazard, so their catwalk network IS the level
## design. They shipped as layout twins: one shared platform list, the same
## ramp, spawn, exit and pickup coordinates, reskinned. This probe keeps them
## apart and keeps each network honest:
##   static - the two levels share almost no catwalk segments, and do not share
##            spawn or exit
##   live   - each level is built; from the player spawn the baked navmesh must
##            reach the exit, every pickup, weapon, lore terminal, vented wave
##            supply and the CENTRE OF EVERY PLATFORM. Distances are 3D, so an
##            upper deck cannot pass from the catwalk underneath it. One
##            non-overlapping segment or one unwalkable ramp fails here.
##   godot --headless --path . --audio-driver Dummy res://tests/hazard_layout_probe.tscn

const SEA_LEVELS := ["lava_world", "water_world"]
const MAX_SHARED := 0.25 # fraction of water_world segments allowed to also exist in lava_world

var _ok := true

func _check(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		print("BAD  %s %s" % [name, detail])
		_ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	_check_not_twins()
	_check_masts_off_decks("water_world")
	for id in SEA_LEVELS:
		await _check_network(id)
		await _check_player_lands_on_spawn_deck(id)
	print("RESULT ", "PASS" if _ok else "FAIL")
	get_tree().quit()

func _seg_key(pl: Dictionary) -> String:
	var p: Vector3 = pl["pos"]
	var s: Vector3 = pl["size"]
	return "%.1f,%.1f,%.1f|%.1f,%.1f" % [p.x, p.y, p.z, s.x, s.z]

func _check_not_twins() -> void:
	var a: Dictionary = LevelDefs.get_def("lava_world")
	var b: Dictionary = LevelDefs.get_def("water_world")
	var lava := {}
	for pl in a.get("platforms", []):
		lava[_seg_key(pl)] = true
	var shared := 0
	var total := 0
	for pl in b.get("platforms", []):
		total += 1
		if lava.has(_seg_key(pl)):
			shared += 1
	var frac := float(shared) / float(maxi(1, total))
	_check("water_world has its own catwalk network", frac <= MAX_SHARED,
		"%d of %d segments are lava_world's" % [shared, total])
	_check("sea levels do not share a spawn", (a["spawn"] as Vector3).distance_to(b["spawn"]) > 4.0)
	_check("sea levels do not share an exit", (a["exit"] as Vector3).distance_to(b["exit"]) > 4.0)
	print("twin check: %d/%d shared segments" % [shared, total])

## Every outdoor light builds a solid mast from the floor up to the lamp
## (LevelBuilder._add_light_pylon). On a sea level a mast on a deck is a pole in
## the middle of a 3.6 m gantry, or under the player spawn. Masts belong in the
## water. (lava_world predates this rule and still has masts on its
## islands, so it is not held to it here.)
func _check_masts_off_decks(id: String) -> void:
	var def: Dictionary = LevelDefs.get_def(id)
	for l in def.get("lights", []):
		var p: Vector3 = l["pos"]
		for pl in def.get("platforms", []):
			var c: Vector3 = pl["pos"]
			var s: Vector3 = pl["size"]
			var on_deck := absf(p.x - c.x) < s.x * 0.5 + 0.3 and absf(p.z - c.z) < s.z * 0.5 + 0.3
			_check("%s: light mast @%v stands in the water, not on a deck" % [id, p], not on_deck)

## The player must come to rest ON the spawn deck: not in the sea below it, and
## not on top of something built over it.
func _check_player_lands_on_spawn_deck(id: String) -> void:
	var lvl: Node = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
	add_child(lvl)
	for i in 10:
		await get_tree().create_timer(0.25).timeout
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var y: float = player.global_position.y if player else -999.0
	_check("%s: player rests on the spawn deck" % id, y > 1.4 and y < 2.0, "y=%.2f" % y)
	lvl.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _check_network(id: String) -> void:
	var def: Dictionary = LevelDefs.get_def(id)
	var lvl: Node = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
	add_child(lvl)
	for i in 10:
		await get_tree().create_timer(0.25).timeout
	var map := get_world_3d().get_navigation_map()
	var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
	var goals: Array = [] # [label, pos]
	goals.append(["exit", def.get("exit", Vector3.ZERO)])
	if def.has("weapon"):
		goals.append(["weapon", def["weapon"]["pos"]])
	for p in def.get("pickups", []):
		goals.append(["pickup " + String(p.get("kind", p.get("type", "?"))), p["pos"]])
	for l in def.get("lore", []):
		goals.append(["lore", l["pos"]])
	for t in def.get("tasks", []):
		for w in t.get("waves", []):
			for s in w.get("supplies", []):
				goals.append(["wave supply", s["pos"]])
	for pl in def.get("platforms", []):
		var c: Vector3 = pl["pos"]
		var top: float = c.y + (pl["size"] as Vector3).y * 0.5
		goals.append(["platform", Vector3(c.x, top, c.z)])
	var reached := 0
	for g in goals:
		var p: Vector3 = g[1]
		var route := NavigationServer3D.map_get_path(map, spawn, p, true)
		var gap := 999.0
		if route.size() > 0:
			gap = (route[route.size() - 1] as Vector3).distance_to(p)
		# 1.6: pickups/terminals float ~0.3-0.5 m above the deck they stand on.
		if gap < 1.6:
			reached += 1
		_check("%s: %s @%v reachable from spawn" % [id, g[0], p], gap < 1.6, "gap %.1f" % gap)
	print("network: %s %d/%d goals reachable" % [id, reached, goals.size()])
	lvl.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
