extends Node
## Data check: flags enemies/pickups/tasks placed inside a hazard-bed ("lava")
## rect — the builder carves those into trenches and does NOT relocate
## entities, so a ground unit placed there ends up below floor level.
##   godot --headless --path . --quit-after 60 res://tools/bed_overlap_check.tscn

func _ready() -> void:
	var total := 0
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		if def.is_empty():
			continue
		var beds: Array = def.get("lava", [])
		if beds.is_empty():
			continue
		for key in ["enemies", "props", "pickups", "extra_weapons"]:
			for e in def.get(key, []):
				var p = e.get("pos")
				if p == null or (p as Vector3).y >= 2.0:
					continue
				for b in beds:
					var bp: Vector3 = b["pos"]
					var bs: Vector2 = b.get("size", Vector2(8, 3))
					if absf(p.x - bp.x) <= bs.x * 0.5 and absf(p.z - bp.z) <= bs.y * 0.5:
						total += 1
						print("BED %s: %s '%s' at %s inside bed %s size %s" % [
							id, key, e.get("type", "?"), p, bp, bs])
	print("BED_CHECK ", "PASS" if total == 0 else "FAIL (%d)" % total)
	get_tree().quit()
