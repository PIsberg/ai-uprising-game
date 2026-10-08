extends Node
## Daily Op (#172): one seeded level a day, outside the campaign.
## (1) daily_op_for is deterministic per date and varies across days: 14 days give
##     several levels and directives, never a boss level or the first level;
## (2) daily_arsenal is the campaign's pacing: no starting-rack guns, nothing first
##     offered on the op's own level or later, and it only grows down the campaign;
## (3) record_daily_clear keeps the day's best, and the streak counts consecutive
##     days (same day unchanged, next day +1, a gap resets to 1); daily_record lets
##     a streak live through the next day and lapse after it; month/leap boundaries;
## (4) the real flow, run from a watcher under root so it survives the scene changes:
##     start today's op from a campaign in progress, check it is HARD with the op's
##     directive and arsenal and that savegame.cfg is byte-identical, clear it, and
##     check the win screen says DAILY OP COMPLETE, the clear lands in records.cfg,
##     Continue goes back to the main menu, the menu button shows the clear, and the
##     campaign's difficulty, guns, level index and map frontier are all back.
## Player files: the probe never writes savegame.cfg (it compares its bytes, or its
## absence, before and after), and it copies records.cfg to RECORDS_BAK on disk before
## writing it, so a run killed half-way is undone by the next run's start.
##   godot --headless --path . --audio-driver Dummy res://tests/daily_op_probe.tscn

const RIFLE := "res://scenes/weapons/rifle.tscn"
const RECORDS_BAK := "user://records.cfg.daily_op_probe.bak"
const NO_FILE := "<no records.cfg>" ## RECORDS_BAK content when there was nothing to keep
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	# The probe scene is current_scene and dies on the first change_scene: hand the
	# run to a copy of this node parked under root, which survives scene changes.
	if get_tree().current_scene == self:
		var w := Node.new()
		w.name = "DailyOpWatcher"
		w.set_script(get_script())
		get_tree().root.add_child.call_deferred(w)
		return
	_run.call_deferred()

func _run() -> void:
	if FileAccess.file_exists(RECORDS_BAK):
		_restore_records() # an earlier run died before restoring
	var keep := FileAccess.get_file_as_bytes(GameState.RECORDS_PATH) if FileAccess.file_exists(GameState.RECORDS_PATH) \
		else NO_FILE.to_utf8_buffer()
	var f := FileAccess.open(RECORDS_BAK, FileAccess.WRITE)
	f.store_buffer(keep)
	f.close()
	_pure_checks()
	await _flow_checks()
	_restore_records()
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)

func _restore_records() -> void:
	var keep := FileAccess.get_file_as_bytes(RECORDS_BAK)
	if keep == NO_FILE.to_utf8_buffer():
		if FileAccess.file_exists(GameState.RECORDS_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.RECORDS_PATH))
	else:
		var f := FileAccess.open(GameState.RECORDS_PATH, FileAccess.WRITE)
		f.store_buffer(keep)
		f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RECORDS_BAK))

## The save's bytes, or an empty array when there is none: "untouched" covers both.
func _save_bytes() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(GameState.SAVE_PATH) if FileAccess.file_exists(GameState.SAVE_PATH) else PackedByteArray()

func _pure_checks() -> void:
	var camp := GameState.campaign()
	# 1. Deterministic, varied, never a boss or the first level.
	var a: Dictionary = GameState.daily_op_for("2026-10-09")
	_check("same date, same op", a == GameState.daily_op_for("2026-10-09") and not a.is_empty(), str(a))
	var levels := {}
	var dirs := {}
	var bad := []
	for i in 14:
		var d := _date_plus("2026-10-01", i)
		var op: Dictionary = GameState.daily_op_for(d)
		levels[op["level"]] = true
		dirs[op["directive"]] = true
		var idx := camp.find(op["level"])
		if idx <= 0 or LevelDefs.level_is_boss(GameState.level_id_from_path(String(op["level"]))):
			bad.append("%s %s" % [d, op["level"]])
	_check("14 days pick only non-boss campaign levels after the first", bad.is_empty(), str(bad))
	_check("14 days give at least 5 levels and 3 directives", levels.size() >= 5 and dirs.size() >= 3,
		"%d levels, %d directives" % [levels.size(), dirs.size()])

	# 2. Arsenal follows the campaign's pacing.
	var first_offer := {}
	for i in camp.size():
		var def: Dictionary = LevelDefs.get_def(GameState.level_id_from_path(String(camp[i])))
		var scenes: Array = []
		if (def.get("weapon", {}) as Dictionary).has("scene"):
			scenes.append(String(def["weapon"]["scene"]))
		for x in def.get("extra_weapons", []):
			scenes.append(String((x as Dictionary).get("scene", "")))
		for sc in scenes:
			if sc != "" and not first_offer.has(sc):
				first_offer[sc] = i
	var prev: Array[String] = []
	var monotone := true
	var paced := true
	for i in range(1, camp.size()):
		var ars: Array[String] = GameState.daily_arsenal(String(camp[i]))
		for sc in ars:
			if GameState.BASE_LOADOUT.has(sc) or int(first_offer.get(sc, 999)) >= i or not ResourceLoader.exists(sc):
				paced = false
				print("  bad arsenal entry on level %d: %s" % [i, sc])
		for sc in prev:
			if not ars.has(sc):
				monotone = false
		prev = ars
	_check("arsenal holds only guns first offered before the op's level", paced)
	_check("arsenal only grows down the campaign", monotone, "%d guns by the last level" % prev.size())

	# 3. Records: best per day, streaks, date arithmetic.
	_clear_daily_section()
	var r1: Dictionary = GameState.record_daily_clear("2026-10-01", 500)
	var r2: Dictionary = GameState.record_daily_clear("2026-10-01", 300)
	var r3: Dictionary = GameState.record_daily_clear("2026-10-02", 200)
	var r4: Dictionary = GameState.record_daily_clear("2026-10-04", 900)
	_check("first clear: best 500, new best, streak 1", r1["best"] == 500 and r1["new_best"] and r1["streak"] == 1, str(r1))
	_check("a lower replay keeps 500 and the streak", r2["best"] == 500 and not r2["new_best"] and r2["streak"] == 1, str(r2))
	_check("the next day: streak 2", r3["streak"] == 2, str(r3))
	_check("after a gap: streak 1", r4["streak"] == 1 and r4["best"] == 900, str(r4))
	var on_day: Dictionary = GameState.daily_record("2026-10-04")
	var day_after: Dictionary = GameState.daily_record("2026-10-05")
	var two_after: Dictionary = GameState.daily_record("2026-10-06")
	_check("daily_record on the day: cleared, best 900", on_day["cleared_today"] and on_day["best"] == 900, str(on_day))
	_check("...the day after: not cleared, streak still alive", not day_after["cleared_today"] and day_after["best"] == 0 and day_after["streak"] == 1, str(day_after))
	_check("...two days after: streak lapsed", two_after["streak"] == 0, str(two_after))
	_check("day before across month and leap boundaries",
		GameState._day_before("2026-03-01") == "2026-02-28" and GameState._day_before("2028-03-01") == "2028-02-29"
		and GameState._day_before("2027-01-01") == "2026-12-31")
	_clear_daily_section()

func _flow_checks() -> void:
	# A campaign in progress, in memory only: NORMAL, one extra gun, level 4 of the map.
	GameState.difficulty = GameState.Difficulty.NORMAL
	GameState.unlocked_weapons.clear()
	GameState.unlocked_weapons.append(RIFLE)
	GameState.level_index = 3
	GameState.max_level_reached = 4
	GameState.current_level_path = String(GameState.campaign()[3])
	var save_before := _save_bytes()
	var op: Dictionary = GameState.daily_op_for(GameState.today_string())

	GameState.start_daily_op()
	_check("op is running on HARD with its directive", GameState.is_daily_op()
		and GameState.difficulty == GameState.Difficulty.HARD and GameState.directive_id == op["directive"],
		"%s %s" % [GameState.difficulty, GameState.directive_id])
	_check("arsenal is the op's, not the campaign's", GameState.unlocked_weapons == GameState.daily_arsenal(String(op["level"])))
	_check("campaign index and frontier untouched", GameState.level_index == 3 and GameState.max_level_reached == 4)
	_check("savegame.cfg untouched by the start", _save_bytes() == save_before)

	var lvl := await _wait_scene(String(op["level"]), 60.0)
	_check("the op's level loaded", lvl != null, String(op["level"]))
	if lvl == null:
		return
	await _frames(30)
	GameState.score = 4321
	GameState.on_level_complete()
	await _frames(5)
	var hud := lvl.get_node_or_null("HUD")
	var title := String(hud.win_title.text) if hud else ""
	_check("win screen says DAILY OP COMPLETE with the score", title.begins_with(tr("DAILY OP COMPLETE")) and title.contains("4321"), title.replace("\n", " | ").left(160))
	var rec: Dictionary = GameState.daily_record()
	_check("the clear is in records.cfg", rec["cleared_today"] and rec["best"] >= 4321, str(rec))
	_check("savegame.cfg untouched by the clear", _save_bytes() == save_before)

	GameState.advance_level()
	var menu := await _wait_scene(GameState.MAIN_MENU, 20.0)
	_check("Continue goes back to the main menu", menu != null)
	await _frames(3)
	_check("op ended, campaign state handed back", not GameState.is_daily_op()
		and GameState.difficulty == GameState.Difficulty.NORMAL and GameState.unlocked_weapons == [RIFLE]
		and GameState.level_index == 3 and GameState.max_level_reached == 4,
		"%s %s %d %d" % [GameState.difficulty, GameState.unlocked_weapons, GameState.level_index, GameState.max_level_reached])
	var btn: Button = menu.get_node_or_null("Center/VBox/MainButtons/Daily") if menu else null
	_check("menu button shows today's clear", btn != null and btn.text.begins_with("✔") and btn.text.contains("4321"), btn.text if btn else "no button")
	_check("savegame.cfg still byte-identical", _save_bytes() == save_before)

func _wait_scene(path: String, timeout_s: float) -> Node:
	var until := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and cs.scene_file_path == path:
			return cs
	return null

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _clear_daily_section() -> void:
	var cf := ConfigFile.new()
	cf.load(GameState.RECORDS_PATH)
	if cf.has_section("daily"):
		cf.erase_section("daily")
	cf.save(GameState.RECORDS_PATH)

func _date_plus(date: String, days: int) -> String:
	return Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(date + "T12:00:00") + days * 86400)
