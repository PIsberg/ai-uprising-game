extends Node
## Verifies GameState.save_progress()/load_progress() round-trip EVERY
## run-scoped field a resumed "Continue" depends on — including the Armory
## supplies (supply_ammo/supply_grenades/supply_health, bought permanently
## for the run and re-applied to the player each deploy in player.gd) and
## the once-per-run `_taught` coaching-toast keys (teach_once). Both were
## silently dropped by save/load: a player who bought supplies and quit lost
## them on Continue, and every first-time coaching toast re-fired on a
## resumed run.
##
## Touches the REAL save file (GameState.SAVE_PATH = user://savegame.cfg), so
## it snapshots the dev's file up front and restores it verbatim (or deletes
## the probe's own file if none existed) before the single result/quit point —
## same restore-before-result pattern as benchmark_probe.gd/preset_probe.gd.
##
## No level scene needed — autoloads exist standalone in a probe.
##   godot --headless --path . res://tests/save_probe.tscn

var _fail: Array[String] = []
var _hint_count := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var had_file := FileAccess.file_exists(GameState.SAVE_PATH)
	var backup_bytes := PackedByteArray()
	if had_file:
		var rf := FileAccess.open(GameState.SAVE_PATH, FileAccess.READ)
		backup_bytes = rf.get_buffer(rf.get_length())
		rf.close()

	GameState.teach_hint.connect(func(_t): _hint_count += 1)
	GameState.reset_run()

	# ---- set EVERY run-scoped field to a distinctive, non-default value ----
	GameState.level_index = 7
	GameState.max_level_reached = 9
	GameState.difficulty = GameState.Difficulty.HARD
	GameState.score = 123456
	GameState.kills = 42
	GameState.unlocked_weapons = [GameState.ALL_WEAPONS[2], GameState.ALL_WEAPONS[5]]
	GameState.equipped_weapon = GameState.ALL_WEAPONS[5]
	var i := 1
	for k in GameState.upgrades:
		GameState.upgrades[k] = i
		i += 1
	GameState.seen_enemy_types = {"strider": true, "gunner": true}
	GameState.nemesis = {"name": "Overseer Prime", "kind": "overseer", "rank": 2}
	GameState.supply_ammo = 77
	GameState.supply_grenades = 5
	GameState.supply_health = 88.5
	GameState.teach_once("save_probe_key_a", "test hint A")
	GameState.teach_once("save_probe_key_b", "test hint B")

	# Snapshot expected values BEFORE reset_run() wipes them back out.
	var exp_unlocked: Array = GameState.unlocked_weapons.duplicate()
	var exp_upgrades: Dictionary = GameState.upgrades.duplicate(true)
	var exp_seen: Dictionary = GameState.seen_enemy_types.duplicate(true)
	var exp_nemesis: Dictionary = GameState.nemesis.duplicate(true)
	var exp := {
		"level_index": GameState.level_index,
		"max_level_reached": GameState.max_level_reached,
		"difficulty": GameState.difficulty,
		"score": GameState.score,
		"kills": GameState.kills,
		"equipped_weapon": GameState.equipped_weapon,
		"supply_ammo": GameState.supply_ammo,
		"supply_grenades": GameState.supply_grenades,
		"supply_health": GameState.supply_health,
	}

	GameState.save_progress()

	# ---- wipe the run, including what reset_run() alone does NOT clear ----
	GameState.reset_run()
	GameState.level_index = 0
	GameState.max_level_reached = 0
	GameState.difficulty = GameState.Difficulty.NORMAL
	GameState.unlocked_weapons.clear()
	GameState.equipped_weapon = ""
	for k in GameState.upgrades:
		GameState.upgrades[k] = 0

	var ok := GameState.load_progress()
	_check(ok, "load_progress() returns true")

	_check(GameState.level_index == exp["level_index"], "level_index round-trips")
	_check(GameState.max_level_reached == exp["max_level_reached"], "max_level_reached round-trips")
	_check(GameState.difficulty == exp["difficulty"], "difficulty round-trips")
	_check(GameState.score == exp["score"], "score round-trips")
	_check(GameState.kills == exp["kills"], "kills round-trips")
	_check(GameState.unlocked_weapons == exp_unlocked,
		"unlocked_weapons round-trips (got %s)" % [GameState.unlocked_weapons])
	_check(GameState.equipped_weapon == exp["equipped_weapon"], "equipped_weapon round-trips")
	_check(GameState.upgrades == exp_upgrades, "upgrades round-trips (got %s)" % [GameState.upgrades])
	_check(GameState.seen_enemy_types == exp_seen,
		"seen_enemy_types round-trips (got %s)" % [GameState.seen_enemy_types])
	_check(GameState.nemesis == exp_nemesis, "nemesis round-trips (got %s)" % [GameState.nemesis])
	_check(GameState.supply_ammo == exp["supply_ammo"], "supply_ammo round-trips (got %d)" % GameState.supply_ammo)
	_check(GameState.supply_grenades == exp["supply_grenades"],
		"supply_grenades round-trips (got %d)" % GameState.supply_grenades)
	_check(is_equal_approx(GameState.supply_health, exp["supply_health"]),
		"supply_health round-trips (got %.2f)" % GameState.supply_health)

	# ---- _taught round-trips: an already-taught key stays suppressed ----
	var count_before := _hint_count
	GameState.teach_once("save_probe_key_a", "should NOT re-fire")
	_check(_hint_count == count_before, "restored _taught key does not re-emit teach_hint")
	GameState.teach_once("save_probe_brand_new", "should fire")
	_check(_hint_count == count_before + 1, "signal still fires for a genuinely new key (sanity check)")

	# ---- restore the dev's real save file before printing the result ----
	if had_file:
		var wf := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
		wf.store_buffer(backup_bytes)
		wf.close()
	elif FileAccess.file_exists(GameState.SAVE_PATH):
		DirAccess.remove_absolute(GameState.SAVE_PATH)

	GameState.reset_run() # leave the singleton clean for anything that follows this probe

	print("RESULT %s" % ("PASS" if _fail.is_empty() else "FAIL"))
	if not _fail.is_empty():
		print("failed: %s" % ", ".join(_fail))
	get_tree().quit(0 if _fail.is_empty() else 1)
