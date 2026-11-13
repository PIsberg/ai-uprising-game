extends Node
## Probe: the BRUTE's SHIELD RUSH in the built levels (#482, item 1).
## brute_rush_probe checks the rush on a flat floor, a synthetic deck and a
## hand-made navmesh. The rush is a straight line of up to 14 m with no
## pathfinding, so what it does at a real lava bed, a deck edge, a tower ramp or
## a bulkhead was unchecked, and a BRUTE that ends somewhere it cannot walk back
## from stalls a kill-all objective.
## Every level scene is built (a BRUTE can arrive anywhere as a wave, an elite
## or a bounty, and the hazards worth checking are in levels that author none),
## its own robots are switched off, and probe BRUTEs are rushed from:
##   - every authored BRUTE's spawn point;
##   - RANDOM_STARTS seeded points on the navmesh (decks and floor alike);
##   - a point 3 m outside each side of every hazard bed.
## From each start, eight BRUTEs run the eight compass lines at once (they do
## not collide with each other), through the real end of the tell: the footing
## check, the run, the wall stun or the miss. Each must end:
##   - outside every hazard bed;
##   - on the navmesh, without having fallen (FALL_FRAMES in the air is a drop of
##     about 0.9 m: over the RUSH_DROP its footing check allows);
##   - with a path back to its start.
## A rush refused at the tell (no footing ahead) is held where it stands. One
## that is hurt or killed on its line (a laser gate, the convoy's road) is
## listed as a NOTE and not failed: it strands nothing.
## Timed in physics frames.
##   godot --headless --path . --audio-driver Dummy res://tests/brute_rush_levels_probe.tscn
##   ... -- levels=lava_world,gpt   one or more levels; -- verbose   every run

const LevelIds := preload("res://tests/level_ids.gd")
const Triage := preload("res://tests/ramp_walk_triage.gd")
const BRUTE := "res://scenes/enemies/brute.tscn"
const RANDOM_STARTS := 10
const DIRS := 8
const NAV_SNAP := 0.6 ## metres (XZ) a resting BRUTE may be from the navmesh
const HOME := 1.5 ## metres the path back may end from the start
const ON_GRAPH := 0.3 ## metres the way from the spawn may end from a start: nearer than an island can sit
const FALL_FRAMES := 25 ## physics frames off the floor in one go that count as a fall

var ok := true
var _runs := 0
var _ran := 0 ## rushes that left the start (the rest were refused at the tell)
var _stunned := 0
var _launched := 0 ## rushes a jump pad or bumper threw: the rush ends, nothing to judge
var _hurt := 0 ## rushes that took damage or died on the line: reported, not failed
var _levels := 0
var _verbose := false

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _ids() -> Array:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("levels="):
			return Array(a.substr(7).split(",", false))
	return Triage.level_ids()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _run() -> void:
	_verbose = OS.get_cmdline_user_args().has("verbose")
	GameState.set_state(GameState.State.PLAYING)
	for id: String in _ids():
		var path := "res://scenes/levels/level_%s.tscn" % id
		if not ResourceLoader.exists(path):
			continue
		seed(hash(id))
		var lvl: Node = (load(path) as PackedScene).instantiate()
		add_child(lvl)
		var player: CharacterBody3D = null
		for i in 150: # build + navmesh bake
			if player == null:
				player = get_tree().get_first_node_in_group("player") as CharacterBody3D
				if player:
					player.set("_god", true)
			await get_tree().physics_frame
		var authored: Array = []
		for e in get_tree().get_nodes_in_group("enemy"):
			if e is EnemyBrute:
				authored.append((e as Node3D).global_position)
			# Off, not freed: clearing a level's robots completes its kill-all.
			e.process_mode = Node.PROCESS_MODE_DISABLED
			if e is CollisionObject3D:
				(e as CollisionObject3D).collision_layer = 0
		await _level(id, lvl, authored)
		LevelIds.unload(lvl)
		await get_tree().process_frame
		await get_tree().process_frame
	_check("the rush was run in every level with a navmesh", _levels >= _ids().size() - 2, "%d of %d level(s)" % [_levels, _ids().size()])
	_check("rushes left their start and some hit a wall", _ran > _runs / 4 and _stunned > 0,
		"%d of %d ran, %d stunned on a wall, %d thrown by a pad, %d hurt on the line" % [_ran, _runs, _stunned, _launched, _hurt])
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

func _level(id: String, lvl: Node, authored: Array) -> void:
	var probe_node := get_tree().get_first_node_in_group("player") as Node3D
	var map: RID = (probe_node if probe_node else (lvl as Node3D)).get_world_3d().navigation_map
	if NavigationServer3D.map_get_regions(map).is_empty():
		print("RUSH %s: no navmesh, skipped" % id)
		return
	# Where the level's robots walk from: the navmesh under the player's spawn.
	var home := Vector3.INF
	if probe_node:
		home = NavigationServer3D.map_get_closest_point(map, probe_node.global_position)
	var starts: Array = authored.duplicate()
	# Seeded here, not only before the build: what the build draws from the RNG
	# differs run to run, and the same starts every run is what makes a red
	# result reproducible.
	seed(hash(id) + 482)
	for i in RANDOM_STARTS:
		starts.append(NavigationServer3D.map_get_random_point(map, 1, false))
	for h in get_tree().get_nodes_in_group("hazard"):
		if h is LavaHazard:
			var c: Vector3 = (h as Node3D).global_position
			var s: Vector2 = (h as LavaHazard).size
			for off: Vector3 in [Vector3(s.x * 0.5 + 3.0, 0, 0), Vector3(-s.x * 0.5 - 3.0, 0, 0), Vector3(0, 0, s.y * 0.5 + 3.0), Vector3(0, 0, -s.y * 0.5 - 3.0)]:
				var near := NavigationServer3D.map_get_closest_point(map, c + off)
				if Vector2(near.x - c.x - off.x, near.z - c.z - off.z).length() < 1.5:
					starts.append(near)
	var scene := load(BRUTE) as PackedScene
	var rows: Array = [] ## {b, st, dir, ran, stunned, air, air_max}
	for st: Vector3 in starts:
		for k in DIRS:
			var b: EnemyBrute = scene.instantiate()
			lvl.add_child(b)
			b.global_position = st + Vector3.UP * 0.1
			var a := TAU * float(k) / float(DIRS)
			rows.append({"b": b, "st": st, "dir": Vector3(sin(a), 0.0, cos(a)), "ran": false, "stunned": false, "air": 0, "air_max": 0})
	await _frames(20) # deferred stat sync, model fit, landing on the floor
	# A start only counts if a BRUTE can stand there: on the floor, on the navmesh.
	# (A random point under a deck, or in a level whose navmesh is not where its
	# floor is, would otherwise be reported as a rush that went wrong.)
	var live: Array = []
	var unusable := 0
	for row: Dictionary in rows:
		var b = row["b"]
		var st: Vector3 = row["st"]
		var standing: bool = is_instance_valid(b) and (b as EnemyBrute).is_on_floor() and (b as EnemyBrute).state != EnemyBase.State.DEAD
		if standing:
			var at := Vector3(st.x, (b as EnemyBrute).global_position.y, st.z)
			var nav := NavigationServer3D.map_get_closest_point(map, at)
			standing = Vector2(nav.x - at.x, nav.z - at.z).length() <= NAV_SNAP and absf(nav.y - at.y) <= 1.0 and not _in_bed(at)
			# ...and that a BRUTE could have walked to: the navmesh has islands (a
			# crate top, a sliver behind cover) no robot is ever on.
			if standing and home != Vector3.INF:
				var reach := NavigationServer3D.map_get_path(map, home, nav, true)
				standing = not reach.is_empty() and reach[reach.size() - 1].distance_to(nav) <= ON_GRAPH
			row["nav"] = nav
		if not standing:
			unusable += 1
			if is_instance_valid(b):
				(b as Node).queue_free()
			continue
		live.append(row)
	for row: Dictionary in live:
		var b: EnemyBrute = row["b"]
		var st: Vector3 = row["st"]
		# The last instant of the tell, facing down the line: the next tick takes
		# the line from where it faces, checks its footing and runs (or refuses).
		b.global_position = Vector3(st.x, b.global_position.y, st.z)
		row["st"] = b.global_position
		b.velocity = Vector3.ZERO
		b.look_at(b.global_position + (row["dir"] as Vector3), Vector3.UP)
		b.target = null
		b.state = EnemyBase.State.CHASE
		b.set("_provoked", 0.0)
		b.set("_rush_cd", 0.0)
		b.set("_rush_t", 0.0)
		b.rush = EnemyBrute.Rush.TELL
		row["hp"] = b.hp.current_health
	# The run is RUSH_TIME at most; then it hangs open for RUSH_MISS_OPEN or more.
	# Judge it while it still hangs open, before its own AI walks it anywhere.
	var limit := int((EnemyBrute.RUSH_TIME + EnemyBrute.RUSH_MISS_OPEN * 0.6) * 60.0)
	for i in limit:
		await get_tree().physics_frame
		for row: Dictionary in live:
			var b = row["b"]
			if not is_instance_valid(b):
				continue
			var br := b as EnemyBrute
			if br.rush == EnemyBrute.Rush.RUSH:
				row["ran"] = true
			elif br.rush == EnemyBrute.Rush.OPEN and float(br.get("_rush_t")) > EnemyBrute.RUSH_MISS_OPEN + 0.05:
				row["stunned"] = true # only a wall leaves it open this long
			elif br.rush == EnemyBrute.Rush.NONE and not row["ran"] and br.process_mode != Node.PROCESS_MODE_DISABLED:
				# Refused at the tell (no footing on the line). Hold it there: left
				# alone its AI walks off after the player, which is not the rush.
				br.process_mode = Node.PROCESS_MODE_DISABLED
			if float(br.get("_launch_t")) > 0.0:
				row["launched"] = true
			if row["ran"]:
				row["air"] = 0 if br.is_on_floor() else int(row["air"]) + 1
				row["air_max"] = maxi(int(row["air_max"]), int(row["air"]))
	var bad: Array = []
	var hurt_here: Array = []
	var ran := 0
	for row: Dictionary in live:
		var b = row["b"]
		var st: Vector3 = row["st"]
		var dir: Vector3 = row["dir"]
		_runs += 1
		if not is_instance_valid(b):
			_hurt += 1
			hurt_here.append("from %s along %s: killed" % [st, dir])
			continue
		var br := b as EnemyBrute
		var p := br.global_position
		var why: Array[String] = []
		if row["ran"]:
			ran += 1
		if row["stunned"]:
			_stunned += 1
		if br.state == EnemyBase.State.DEAD or br.hp.current_health < float(row["hp"]) - 0.01:
			# Not a failure: nothing strands it, and a BRUTE baited through a laser
			# is the player's doing. Counted so the playtest knows where (#482).
			_hurt += 1
			hurt_here.append("from %s along %s to %s: %.0f of %.0f hp%s" % [st, dir, p, br.hp.current_health, float(row["hp"]), ", dead" if br.state == EnemyBase.State.DEAD else ""])
		if _in_bed(p):
			why.append("in a hazard bed")
		var on_nav := NavigationServer3D.map_get_closest_point(map, p)
		if Vector2(on_nav.x - p.x, on_nav.z - p.z).length() > NAV_SNAP or absf(on_nav.y - p.y) > 1.0:
			why.append("off the navmesh (nearest %s)" % on_nav)
		if row.get("launched", false):
			_launched += 1 # a jump pad took it: the rush ended there, it lands on floor
		elif int(row["air_max"]) > FALL_FRAMES:
			why.append("fell (%.2f s in the air, %.2f m down)" % [int(row["air_max"]) / 60.0, st.y - p.y])
		var back := NavigationServer3D.map_get_path(map, on_nav, row["nav"], true)
		if back.is_empty() or back[back.size() - 1].distance_to(row["nav"]) > HOME:
			var from_home := NavigationServer3D.map_get_path(map, home, on_nav, true) if home != Vector3.INF else PackedVector3Array()
			var home_gap := from_home[from_home.size() - 1].distance_to(on_nav) if not from_home.is_empty() else -1.0
			why.append("no path back (it ends %.1f m from the start; from the spawn the way here ends %.1f m short; nav under it %s)" % [
				back[back.size() - 1].distance_to(st) if not back.is_empty() else -1.0, home_gap, on_nav])
		if _verbose or not why.is_empty():
			var line := "from %s along %s, %.1f m to %s (%s): %s" % [st, dir, Vector2(p.x - st.x, p.z - st.z).length(), p,
				"stunned on a wall" if row["stunned"] else ("ran" if row["ran"] else "refused"), ", ".join(why) if not why.is_empty() else "ok"]
			if why.is_empty():
				print("RUSH %s %s" % [id, line])
			else:
				bad.append(line)
	_ran += ran
	_levels += 1
	_check("%s: every rush ends on ground it can walk home from" % id, bad.is_empty() and not live.is_empty(),
		"%d start(s) (%d rushes; %d more had no standing room), %d ran%s" % [live.size() / DIRS, live.size(), unusable, ran,
		"" if bad.is_empty() else "; %d bad:
    %s" % [bad.size(), "
    ".join(bad.slice(0, 12))]])
	if not hurt_here.is_empty():
		print("NOTE %s: %d rush(es) were hurt on the line:
    %s" % [id, hurt_here.size(), "
    ".join(hurt_here.slice(0, 6))])
	for row: Dictionary in rows:
		if is_instance_valid(row["b"]):
			(row["b"] as Node).queue_free()
	await _frames(2)

## Is `p` in a hazard bed, at the bed's height? (EnemyBase._pos_in_hazard asks
## about the footprint alone, which is also true on a deck 10 m over the lava.)
func _in_bed(p: Vector3) -> bool:
	for h in get_tree().get_nodes_in_group("hazard"):
		if h is LavaHazard:
			var hp: Vector3 = (h as Node3D).global_position
			var s: Vector2 = (h as LavaHazard).size
			if absf(p.x - hp.x) <= s.x * 0.5 and absf(p.z - hp.z) <= s.y * 0.5 and absf(p.y - hp.y) <= 1.5:
				return true
	return false
