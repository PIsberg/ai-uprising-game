extends Node
## Difficulty assessment: walks the CAMPAIGN in order and computes a per-level
## THREAT INDEX from each level's enemy roster (measured per-enemy DPS + a
## survivability term hp/40, summed over count), to check the campaign RAMPS UP.
## Then models the EASY/NORMAL/HARD multipliers into a combined factor to check
## the tiers spread sensibly. Pure data — run as a scene (autoloads needed):
## godot --headless --path . --quit-after 60 res://tests/difficulty_curve.tscn

# threat = measured eval DPS + hp/40 (survivability/exposure). Bosses dominate via hp.
const THREAT := {
	"drone": 17.7, "android": 16.3, "spider": 14.4, "mech": 20.8, "skitter": 5.4,
	"vacuum": 6.9, "hunter": 8.0, "reaper": 12.6, "strider": 12.9, "sniper": 16.3,
	"seeker": 6.7, "brute": 17.0, "gunner": 14.8, "raptor": 9.9, "mender": 6.0,
	"sentinel": 10.6, "mauler": 22.3, "ravager": 12.8, "warmech": 15.5, "alien": 10.0,
	"dog": 9.8, "server": 12.6,
	"colossus": 105.0, "titan": 93.0, "overseer": 59.5, "archon": 95.0,
	"terminator": 32.0, "smasher": 120.0,
	# Measured via enemy_eval_probe.tscn. shark's live DPS reads 0 there — its
	# breach attack needs an actual water surface to trigger, which the eval rig's
	# dry flat plane doesn't provide — so its figure is hand-derived instead:
	# bite_damage 28 / ~2.9s average breach cycle (enemy_shark.gd) + hp/40.
	"fishbot": 21.8, "shark": 13.0,
	"warbot": 23.0, "enforcer": 9.0, "ripper": 15.0, "whirlwind": 28.7,
	"optic": 7.1, "roller": 16.4, "gunslinger": 7.6, "breaker": 25.5,
}

func _ready() -> void:
	print("=== CAMPAIGN DIFFICULTY CURVE (level roster threat index) ===")
	print("%-3s %-14s %6s %6s  %5s  %s" % ["#", "level", "threat", "delta", "boss?", "warn"])
	var prev := 0.0
	var idx := 0
	var dips: Array = []
	for path in GameState.CAMPAIGN:
		idx += 1
		var id: String = GameState.level_id_from_path(path)
		var def: Dictionary = LevelDefs.get_def(id)
		var threat := 0.0
		var unknown: Array = []
		for e in def.get("enemies", []):
			var t: String = e.get("type", "")
			var c: int = int(e.get("count", 1))
			if THREAT.has(t):
				threat += THREAT[t] * c
			elif t != "":
				unknown.append(t)
		var boss := LevelDefs.level_is_boss(id)
		var delta := threat - prev
		var warn := ""
		# A non-boss level that DROPS vs the previous non-trivial level is a dip in
		# the ramp; flag it (boss spikes + the post-boss reset are expected).
		if idx > 1 and delta < -1.0 and not boss:
			warn = "DIP %.0f" % delta
			dips.append("%s (%.0f -> %.0f)" % [id, prev, threat])
		if not unknown.is_empty():
			warn += " ?" + str(unknown)
		print("%-3d %-14s %6.0f %6.0f  %5s  %s" % [idx, id, threat, delta, ("BOSS" if boss else ""), warn])
		prev = threat
	print("")
	print("DIPS (non-boss levels easier than the one before): ", dips if not dips.is_empty() else "none")

	# ---- tier spread model ----
	print("\n=== DIFFICULTY TIER SPREAD (combined incoming-damage factor) ===")
	for tier in [GameState.Difficulty.EASY, GameState.Difficulty.NORMAL, GameState.Difficulty.HARD]:
		var cfg: Dictionary = GameState.DIFFICULTY_CONFIG[tier]
		var cnt: float = cfg["enemy_count_mult"]
		var cd: float = 1.0 / cfg["cooldown_mult"]                 # faster cd -> more dps
		var acc: float = clampf(1.0 - cfg["aim_spread_deg"] / 28.0, 0.25, 1.0) # accuracy/hit-rate
		var hpf: float = sqrt(cfg["health_mult"])                  # tankier -> longer exposure
		var combined: float = cnt * cd * acc * hpf
		print("%-7s count×%.2f  dps×%.2f  acc×%.2f  exposure×%.2f  =>  factor %.2f" % [
			cfg["label"], cnt, cd, acc, hpf, combined])
	print("DIFFICULTY_CURVE_DONE")
	get_tree().quit()
