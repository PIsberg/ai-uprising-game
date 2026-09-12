extends Node
## Diagnostic: how much room does each level give the player at spawn?
##
## Reports, per campaign level, the distance from the player spawn to the nearest
## enemy that is AWAKE FROM THE START (no "trigger" key, or a trigger radius that
## already contains the spawn), since those are the only ones that can engage
## during the opening seconds. Other triggered enemies wake when the player
## closes on them, so they cannot contribute to spawn-camping.
##
## The point is the campaign's own convention: most levels cluster around a
## comfortable opening distance, and an outlier is what a spawn-DPS spike looks
## like in the data.
##   godot --headless --path . --audio-driver Dummy res://tests/opening_distance_check.tscn

func _ready() -> void:
	var ids: PackedStringArray = []
	for path in GameState.CAMPAIGN:
		ids.append(path.get_file().trim_prefix("level_").trim_suffix(".tscn"))
	var rows: Array = []
	for id in ids:
		var def: Dictionary = LevelDefs.get_def(id)
		if def.is_empty():
			continue
		var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
		var best := 1e9
		var who := "-"
		var awake := 0
		for e in def.get("enemies", []):
			var p: Vector3 = e.get("pos", Vector3.ZERO)
			var d: float = Vector2(p.x - spawn.x, p.z - spawn.z).length()
			# A triggered enemy wakes on approach — unless its trigger radius
			# already contains the spawn, in which case it is awake at start in
			# every way that matters (this is what the idle-DPS spikes were).
			if e.has("trigger") and d > float(e["trigger"]):
				continue
			awake += 1
			if d < best:
				best = d
				who = str(e.get("type", "?"))
		rows.append({"id": id, "d": best, "who": who, "n": awake})
	rows.sort_custom(func(a, b): return a["d"] < b["d"])
	print("%-13s %8s  %-10s %s" % ["level", "nearest", "type", "awake-at-start"])
	for r in rows:
		var d: float = r["d"]
		print("%-13s %8s  %-10s %d" % [
			r["id"], ("none" if d > 1e8 else "%.1fm" % d), r["who"], r["n"]])
	# Second pass: name every awake-at-start enemy sitting inside the campaign's
	# own comfortable floor, so the outliers are actionable rather than just visible.
	const FLOOR := 32.0
	print("
-- awake-at-start enemies closer than %.0fm --" % FLOOR)
	for id in ids:
		var def: Dictionary = LevelDefs.get_def(id)
		if def.is_empty():
			continue
		var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
		for e in def.get("enemies", []):
			var p: Vector3 = e.get("pos", Vector3.ZERO)
			var d: float = Vector2(p.x - spawn.x, p.z - spawn.z).length()
			if e.has("trigger") and d > float(e["trigger"]):
				continue
			if d < FLOOR:
				print("  %-13s %-10s at %s  d=%.1fm  (authored %s)" % [
					id, str(e.get("type", "?")), p, d, p / 1.4])
	get_tree().quit()
