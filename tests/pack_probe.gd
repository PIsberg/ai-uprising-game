extends Node3D
## How do robots actually ARRIVE? Each authored enemy is its own EnemySpawner
## with its own trigger_radius, so they wake independently as the player closes.
## This walks the player from spawn to exit and timestamps every spawn, then
## clusters them: a "pack" is a burst of spawns within PACK_WINDOW seconds.
##
## A level whose packs are almost all size 1 drips enemies at the player one at a
## time; a level with mixed packs of 3-5 gives a fight.
##   godot --headless --path . res://tests/pack_probe.tscn

const LEVELS := ["01", "gpt", "gemini", "mistral", "suburb", "claude", "grok", "uplink",
	"alien", "assembly", "sublevel", "frostbreak", "desert", "neon", "crucible", "lava_world"]
const WALK_SPEED := 6.0     ## m/s along the spawn->exit line
## Cluster by PLAYER TRAVEL DISTANCE, not by time: a fast walk crosses many
## trigger radii at once and flatters the numbers. Two robots that wake within a
## few metres of each other arrive together whatever your speed; two that wake
## 10 m apart arrive one at a time however fast you run.
const PACK_DIST := 6.0      ## metres of travel; spawns closer than this are one pack

var _last_comp: Array[int] = [] # distinct chassis per pack, for the level just walked
## A pack trip wakes every squadmate. If the claim flag in EnemySpawner ever
## failed, a robot could be queued twice by two squadmates tripping in different
## frames — so assert the level never fields more robots than it authored.
var _dupe_free: bool = true

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("%-12s %6s %6s %8s %8s  %s" % ["LEVEL", "waves", "spawns", "avg/pack", "max", "pack sizes"])
	var all_packs: Array[int] = []
	var all_comp: Array[int] = []
	for id in LEVELS:
		var packs := await _walk(id)
		all_packs.append_array(packs)
		var total := 0
		var mx := 0
		for p in packs:
			total += p
			mx = maxi(mx, p)
		var avg: float = float(total) / maxf(packs.size(), 1)
		var mono := 0
		for c in _last_comp:
			if c <= 1:
				mono += 1
		all_comp.append_array(_last_comp)
		print("%-12s %6d %6d %8.2f %8d  sizes=%s kinds=%s mono=%d/%d" % [
			id, packs.size(), total, avg, mx, str(packs), str(_last_comp), mono, _last_comp.size()])
	var solo := 0
	for p in all_packs:
		if p == 1:
			solo += 1
	var mono_all := 0
	for c in all_comp:
		if c <= 1:
			mono_all += 1
	print("\nacross %d packs: %d are a SINGLE robot (%.0f%%)" % [
		all_packs.size(), solo, 100.0 * float(solo) / maxf(all_packs.size(), 1)])
	print("%d packs are a SINGLE CHASSIS TYPE (%.0f%%) — no mixed threat" % [
		mono_all, 100.0 * float(mono_all) / maxf(all_comp.size(), 1)])
	print("(solo mini-bosses — MECH, SMASHER — and overwatch SNIPERs are unpacked on purpose)")
	print("RESULT ", "PASS" if _dupe_free else "FAIL")
	get_tree().quit()

func _alive() -> int:
	return get_tree().get_nodes_in_group("enemy").size()

## Chassis names of the live robots, so a pack can be described by WHAT is in it,
## not just how many. A "pack" of six skitters is one robot repeated.
func _live_types() -> Array[String]:
	var out: Array[String] = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.has_method("codex_key"):
			out.append(String(e.call("codex_key")))
	return out

func _walk(id: String) -> Array[int]:
	var path := "res://scenes/levels/level_%s.tscn" % id
	if not ResourceLoader.exists(path):
		return []
	var lvl: Node = (load(path) as PackedScene).instantiate()
	add_child(lvl)
	GameState.set_state(GameState.State.PLAYING)
	for i in 40: # let the level build + bake + untriggered enemies pour in
		await get_tree().physics_frame
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var def: Dictionary = LevelDefs.get_def(id)
	var from: Vector3 = def.get("spawn", Vector3.ZERO)
	var to: Vector3 = def.get("exit", Vector3.ZERO)
	# Ignore the opening pour: only count what the WALK wakes.
	var seen := _alive()
	var events: Array[float] = []   # player travel distance at each spawn
	var ev_types: Array[String] = []
	var prev_types := _live_types()
	var dist := from.distance_to(to)
	var steps := int(dist / (WALK_SPEED * (1.0 / 60.0)))
	for i in steps:
		var f := float(i) / float(maxi(steps, 1))
		player.global_position = from.lerp(to, f) + Vector3.UP * 0.6
		await get_tree().physics_frame
		var travelled := dist * f
		var n := _alive()
		if n > seen:
			# Which chassis just appeared? Diff the live roster.
			var now := _live_types()
			var tally := {}
			for tn in prev_types:
				tally[tn] = int(tally.get(tn, 0)) + 1
			for tn in now:
				if int(tally.get(tn, 0)) > 0:
					tally[tn] = int(tally[tn]) - 1
				else:
					events.append(travelled)
					ev_types.append(tn)
					seen += 1
			prev_types = now
			seen = n
	var authored := 0
	for en in def.get("enemies", []):
		authored += maxi(1, int((en as Dictionary).get("count", 1)))
	if seen > authored:
		print("BAD  %s fielded %d robots but authored %d — a pack spawned a duplicate" % [
			id, seen, authored])
		_dupe_free = false
	lvl.queue_free()
	# EnemySpawner parents its robot to current_scene (this probe's root), NOT to
	# the level — so freeing the level leaves the whole roster standing, and the
	# next level's counts start from the last one's leftovers.
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			(e as Node).queue_free()
	for i in 8:
		await get_tree().physics_frame
	# Cluster into packs and describe each by its composition.
	var packs: Array[int] = []
	_last_comp.clear()
	var i2 := 0
	while i2 < events.size():
		var start: float = events[i2]
		var n2 := 0
		var kinds := {}
		while i2 < events.size() and events[i2] - start <= PACK_DIST:
			kinds[ev_types[i2]] = true
			n2 += 1
			i2 += 1
		packs.append(n2)
		_last_comp.append(kinds.size())
	return packs
