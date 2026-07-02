extends Node
## Audits every campaign level's PATH-GATING and CLIMBING content straight from
## LevelDefs: how much of the arena is blocked (tall walls, lava/water beds)
## versus open floor, and how much vertical route content it has (ramps,
## stairs, platforms, towers). Flags the flattest / most-open offenders so a
## routing pass targets the right levels.
## Run: godot --headless --path . --quit-after 120 tools/level_gating_audit.tscn

func _ready() -> void:
	print("=== LEVEL GATING / CLIMBING AUDIT ===")
	print("%-13s %8s | %5s %5s | %5s %5s %5s %5s | %6s | %s" % [
		"level", "floor", "tallW", "cover", "ramps", "stair", "plats", "towrs", "lava%", "verdict"])
	for path in GameState.CAMPAIGN:
		var id: String = GameState.level_id_from_path(path)
		var def: Dictionary = LevelDefs.get_def(id)
		if def.is_empty():
			print("%-13s (hand-authored scene, no def)" % id)
			continue
		var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
		var floor_area := fs.x * fs.y
		var tall_walls := 0
		var cover_walls := 0
		for w in def.get("walls", []):
			var sz: Vector3 = w.get("size", Vector3.ZERO)
			# >2.2m can't be jumped or mantled (mantle_max_h 1.7) — a true gate.
			if sz.y > 2.2:
				tall_walls += 1
			else:
				cover_walls += 1
		var ramps: int = def.get("ramps", []).size()
		var stairs: int = def.get("stairs", []).size()
		var plats: int = def.get("platforms", []).size()
		var towers: int = def.get("towers", []).size()
		var lava_area := 0.0
		for b in def.get("lava", []):
			var s: Vector2 = (b as Dictionary).get("size", Vector2(8, 3))
			lava_area += s.x * s.y
		var lava_pct := 100.0 * lava_area / maxf(floor_area, 1.0)
		var vertical := ramps + stairs + plats + towers
		var gates := tall_walls + (1 if lava_pct > 8.0 else 0)
		var verdict := ""
		if gates == 0 and vertical <= 2:
			verdict = "OPEN+FLAT (worst)"
		elif gates == 0:
			verdict = "OPEN (no path gating)"
		elif vertical <= 2:
			verdict = "FLAT (no climbing)"
		print("%-13s %4dx%-3d | %5d %5d | %5d %5d %5d %5d | %5.1f%% | %s" % [
			id, int(fs.x), int(fs.y), tall_walls, cover_walls,
			ramps, stairs, plats, towers, lava_pct, verdict])
	print("AUDIT_DONE")
	get_tree().quit()
