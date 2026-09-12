extends Node
## The Damage Taken accessibility assist counts toward the grade like a
## difficulty tier (issue #88): GameState.assist_score_mult() is x0.85 at 50%,
## x1.0 at 100%, x1.10 at 150%, and grade_level() applies it on top of the tier
## multiplier and reports the slider value as stats["assist"] so the debrief can
## name it. Drives grade_level() with a fixed stat line that scores ~92 on
## NORMAL at 100% (an S) and checks the letter moves with the slider:
## 50% -> ~78 -> A, 150% -> 100 -> S. Restores the slider (it persists to
## user://settings.cfg on every set) before quitting.
##   godot --headless --path . --audio-driver Dummy res://tests/grade_assist_probe.tscn

var _fail: Array[String] = []

func _check(cond: bool, label: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var orig: float = GraphicsSettings.damage_taken
	var orig_diff: int = GameState.difficulty
	GameState.difficulty = GameState.Difficulty.NORMAL
	GameState.current_level_path = ""   # no par -> no speed bonus in the mix

	GraphicsSettings.set_damage_taken(1.0)
	_check(is_equal_approx(GameState.assist_score_mult(), 1.0), "100% assist is score-neutral")
	GraphicsSettings.set_damage_taken(0.5)
	_check(is_equal_approx(GameState.assist_score_mult(), 0.85), "50%% assist scores x0.85 (%.3f)" % GameState.assist_score_mult())
	GraphicsSettings.set_damage_taken(1.5)
	_check(is_equal_approx(GameState.assist_score_mult(), 1.10), "150%% assist scores x1.10 (%.3f)" % GameState.assist_score_mult())
	GraphicsSettings.set_damage_taken(0.75)
	_check(is_equal_approx(GameState.assist_score_mult(), 0.925), "75% assist sits halfway (x0.925)")

	# A fixed run: 100% accuracy (45) + 10-combo (30) + 60 damage taken (19) = 94.
	var results := {}
	for dt in [1.0, 0.5, 1.5]:
		GraphicsSettings.set_damage_taken(dt)
		GameState.stat_shots = 100
		GameState.stat_hits = 100
		GameState.max_combo = 10
		GameState.stat_damage_taken = 60.0
		GameState.level_start_ms = Time.get_ticks_msec()
		var r: Dictionary = GameState.grade_level()
		results[dt] = r
		print("  damage_taken %.2f -> grade %s (assist stat %.2f, mult %.3f)" % [dt, r["grade"], r["stats"]["assist"], r["stats"]["assist_mult"]])
	_check(results[1.0]["grade"] == "S", "neutral slider: the fixed run is an S")
	_check(results[0.5]["grade"] == "A", "50% assist drops the same run to an A")
	_check(results[1.5]["grade"] == "S", "150% keeps the S (capped at 100)")
	_check(is_equal_approx(float(results[0.5]["stats"]["assist"]), 0.5), "stats carry the slider value for the debrief")

	GraphicsSettings.set_damage_taken(orig)
	GameState.difficulty = orig_diff
	print("RESULT %s" % ("PASS" if _fail.is_empty() else "FAIL"))
	get_tree().quit(0 if _fail.is_empty() else 1)
