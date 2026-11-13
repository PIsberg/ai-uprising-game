extends RefCounted
## The one list of level ids for every sweep in tests/: read from the level
## scenes on disk, so a new level is covered the day its scene lands (#514).
## Hand-kept lists skipped hivemind, guardrails and convoy in three sweeps and
## two of those levels in the ramp walk. A sweep that must leave a level out
## passes it in `except`, with the reason in a comment where it does.
##   const LevelIds := preload("res://tests/level_ids.gd")
##   for id in LevelIds.all(["convoy"]): ...

const LEVEL_DIR := "res://scenes/levels"
## Scenes named level_*.tscn that are not a level of their own: level_custom is
## the shell the editor's .lvl files load through.
const NOT_LEVELS := ["custom"]

## Sorted ids of every level scene, minus `except`. An exported build lists
## `.tscn.remap`.
static func all(except: Array = []) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(LEVEL_DIR):
		var name := f.trim_suffix(".remap")
		if name.begins_with("level_") and name.ends_with(".tscn"):
			var id := name.trim_prefix("level_").trim_suffix(".tscn")
			if not NOT_LEVELS.has(id) and not except.has(id) and not out.has(id):
				out.append(id)
	out.sort()
	return out

## Free a level a probe built, with the robots it spawned. EnemySpawner parents
## robots to the current scene, beside the level, so `level.queue_free()` alone
## leaves them alive, awake and hunting in every level the probe builds next:
## 15 of 32 multi-level probes carried up to 100 of them into the next level,
## and VACUUMs ate the pickups pickup_reach_sweep was counting (#514, #522).
## tools/check_suite_manifest.py fails a suite or headless probe that frees a
## level with a bare queue_free().
static func unload(level: Node) -> void:
	if not is_instance_valid(level):
		return
	if level.is_inside_tree():
		for e in level.get_tree().get_nodes_in_group("enemy"):
			if not level.is_ancestor_of(e):
				e.queue_free()
	level.queue_free()
