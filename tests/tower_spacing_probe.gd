extends Node
## Two towers whose footprints overlap stack one tower's corner landing inside
## the other's climb: on grok and mistral (#339) the 7 m tower's 4.67 m landing
## hung 1.7 m over the 8 m tower's 2.0 m landing, so the player walked up the
## first corner and stuck there head-first. A tower's spiral runs on a square of
## half-width `radius` around `pos`, and every corner landing reaches
## LANDING_HALF past it (level_builder._build_tower), so two towers need their
## squares that far apart. Data only: reads every level def, builds nothing.
##   godot --headless --path . --audio-driver Dummy res://tests/tower_spacing_probe.tscn

const LANDING_HALF := 1.9 # level_builder._build_tower: keep in sync

func _ready() -> void:
	var fails := 0
	var pairs := 0
	for id in LevelDefs._defs().keys():
		var towers: Array = LevelDefs.get_def(id).get("towers", [])
		for i in towers.size():
			for j in range(i + 1, towers.size()):
				pairs += 1
				var a: Dictionary = towers[i]
				var b: Dictionary = towers[j]
				var pa: Vector3 = a["pos"]
				var pb: Vector3 = b["pos"]
				var reach := float(a.get("radius", 3.6)) + float(b.get("radius", 3.6)) + 2.0 * LANDING_HALF
				var gap := maxf(absf(pa.x - pb.x), absf(pa.z - pb.z)) - reach
				if gap < 0.0:
					fails += 1
					print("  BAD %s: towers at %s and %s overlap by %.1f m" % [id, pa, pb, -gap])
	print("tower pairs checked: %d, overlapping: %d" % [pairs, fails])
	print("RESULT %s" % ("PASS" if fails == 0 and pairs > 0 else "FAIL"))
	get_tree().quit()
