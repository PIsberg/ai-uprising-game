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
