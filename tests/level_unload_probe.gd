extends Node3D
## Probe: LevelIds.unload frees a level together with the robots it spawned
## (#522). EnemySpawner parents robots to the current scene, beside the level,
## so a bare `level.queue_free()` leaves them alive in whatever level a probe
## builds next. In two real levels:
##   - the level's robots are outside the level node (the premise: if this
##     ever stops being true, unload's sweep of group "enemy" can go);
##   - a bare queue_free() leaves every one of them standing;
##   - LevelIds.unload(level) leaves none, in the same frames;
##   - it takes a null level without an error.
##   godot --headless --path . --audio-driver Dummy res://tests/level_unload_probe.tscn

const LevelIds := preload("res://tests/level_ids.gd")
const LEVELS := ["gpt", "neon"] ## two levels with a starting roster

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _robots() -> Array:
	var out: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			out.append(e)
	return out

func _build(id: String) -> Node:
	var lvl: Node = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
	add_child(lvl)
	# The roster warps in over the first seconds: wait for it, 6 s at most.
	for i in 24:
		await get_tree().create_timer(0.25).timeout
		if _robots().size() >= 3:
			break
	return lvl

func _run() -> void:
	GameState.reset_run()
	for id: String in LEVELS:
		# The old way. Not named `lvl`: check_suite_manifest.py fails a probe
		# that frees a variable of that name with a bare queue_free().
		var bare: Node = await _build(id)
		var spawned := _robots()
		var outside := 0
		for e in spawned:
			if not bare.is_ancestor_of(e):
				outside += 1
		_check("%s: the level's robots are outside the level node" % id, spawned.size() >= 3 and outside == spawned.size(), "%d robots, %d outside" % [spawned.size(), outside])
		bare.queue_free()
		await _frames(4)
		var loose := _robots().size()
		_check("%s: a bare queue_free() leaves them standing" % id, loose == spawned.size() and loose > 0, "%d of %d" % [loose, spawned.size()])
		for e in _robots():
			e.queue_free()
		await _frames(4)

		# The helper.
		var lvl: Node = await _build(id)
		var again := _robots().size()
		LevelIds.unload(lvl)
		await _frames(4)
		_check("%s: LevelIds.unload leaves none" % id, again >= 3 and _robots().is_empty() and not is_instance_valid(lvl), "%d before, %d after" % [again, _robots().size()])

	LevelIds.unload(null)
	_check("unload takes a null level", true)

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
