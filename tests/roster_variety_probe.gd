extends Node
## "Are all the robots actually used?"
##
## Every enemy scene must be placed somewhere in the campaign, and every ordinary
## robot should appear in more than one level — a chassis you meet once is a
## cameo, not part of the game's vocabulary. Bosses appear once by design, and a
## few enemies are tied to one biome (SHARK/FISHBOT are underwater, HIVE is the
## hivemind, ALIEN is the alien world), so both are exempted by name.
##   godot --headless --path . res://tests/roster_variety_probe.tscn

const BOSSES := ["archon", "colossus", "manus", "overseer", "smasher", "terminator", "titan"]
const BIOME_LOCKED := ["shark", "fishbot", "hive", "alien"]
const MIN_LEVELS := 2

func _ready() -> void:
	var all: Array[String] = []
	for f in DirAccess.get_files_at("res://scenes/enemies/"):
		if f.ends_with(".tscn"):
			all.append(f.get_basename())

	var levels := {}
	for ch in LevelDefs.CHAPTERS:
		for id in ch["ids"]:
			var def: Dictionary = LevelDefs.get_def(String(id))
			for t in _types_in(def):
				if not levels.has(t):
					levels[t] = []
				if not (levels[t] as Array).has(String(id)):
					(levels[t] as Array).append(String(id))

	var never: Array[String] = []
	var cameo: Array[String] = []
	for e in all:
		var n: int = (levels.get(e, []) as Array).size()
		if n == 0:
			never.append(e)
		elif n < MIN_LEVELS and not BOSSES.has(e) and not BIOME_LOCKED.has(e):
			cameo.append("%s (%s)" % [e, ",".join(levels[e])])

	print("enemy scenes: ", all.size())
	print("placed in >=%d levels: %d" % [MIN_LEVELS, all.size() - never.size() - cameo.size()])
	print("NEVER placed: ", never if never.size() > 0 else "none")
	print("cameo (one level only, not a boss or biome-locked): ", cameo.size())
	for c in cameo:
		print("   ", c)
	var ok := never.is_empty() and cameo.is_empty()
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

## Every enemy type a level places: hand-placed, objective reinforcements, survive
## waves, and an assassinate target.
func _types_in(def: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for e in def.get("enemies", []):
		out.append(String((e as Dictionary).get("type", "")))
	for t in def.get("tasks", []):
		var td: Dictionary = t
		for r in td.get("reinforce", []):
			out.append(String((r as Dictionary).get("type", "")))
		for w in td.get("waves", []):
			for r in (w as Dictionary).get("enemies", []):
				out.append(String((r as Dictionary).get("type", "")))
		if td.has("enemy"):
			out.append(String(td["enemy"]))
	return out
