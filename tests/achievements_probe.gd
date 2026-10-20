extends Node
## Probe: ACHIEVEMENTS (scripts/autoload/achievements.gd).
## (1) every definition has a title, a description and a translated title;
## (2) each trigger unlocks its achievement through the real GameState signal:
##     a kill, the GODLIKE rampage tier, a perfect dodge, a CASCADE x6, OVERLOAD,
##     ADRENALINE, a settled nemesis, an S rank, a HARD clear without a death, a
##     hijack, a network breach, each ending (and all three), an UPRISING clear
##     and a 3-day Daily Op streak; lifetime counters unlock at their target
##     (10 executions, 5 bounties, 500 kills), not before;
## (3) an unlock pops the toast once and is never re-announced;
## (4) unlocks and counters persist across a reload of the file;
## (5) the main menu's button counts them and opens the list.
##   godot --headless --path . --audio-driver Dummy res://tests/achievements_probe.tscn

const FILE := "user://achievements_probe.cfg"
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	if get_parent() != get_tree().root or get_tree().current_scene == self:
		var runner := Node.new()
		runner.set_script(get_script())
		get_tree().root.add_child.call_deferred(runner)
		return
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _has(id: String) -> bool:
	return Achievements.is_unlocked(id)

func _run() -> void:
	Achievements.use_file(FILE, true) # a fresh scratch file, persisted
	# 1. Definitions.
	TranslationServer.set_locale("de")
	var defs_ok := true
	for id in Achievements.DEFS:
		var d: Dictionary = Achievements.DEFS[id]
		# Titles like OVERLOAD read the same in German, so the description proves the row.
		var has_text := String(d.get("title", "")) != "" and String(d.get("desc", "")) != ""
		defs_ok = defs_ok and has_text and TranslationServer.translate(String(d["desc"])) != String(d["desc"])
	TranslationServer.set_locale("en")
	_check("every achievement has a title and a German description", defs_ok)

	# 2. Triggers through the real signals.
	GameState.enemy_killed.emit(100, "DRONE")
	_check("FIRST BLOOD on the first kill", _has("first_blood"))
	GameState.rampage_changed.emit(2, "UNSTOPPABLE")
	_check("UNSTOPPABLE is not GODLIKE", not _has("godlike"))
	GameState.rampage_changed.emit(3, "GODLIKE")
	_check("GODLIKE at the top rampage tier", _has("godlike"))
	GameState.perfect_dodge.emit()
	_check("UNTOUCHABLE on a perfect dodge", _has("untouchable"))
	GameState.cascade_chain.emit(5, Vector3.ZERO)
	_check("a CASCADE x5 is not STACK OVERFLOW", not _has("overflow"))
	GameState.cascade_chain.emit(6, Vector3.ZERO)
	_check("STACK OVERFLOW at x6", _has("overflow"))
	GameState.ultimate_fired.emit()
	_check("OVERLOAD fired", _has("overload"))
	GameState.adrenaline_changed.emit(true)
	_check("CLUTCH on ADRENALINE", _has("clutch"))
	GameState.nemesis_down.emit("KX-101 'NULLPOINT'", 500)
	_check("GRUDGE SETTLED on a nemesis kill", _has("grudge"))
	GameState.level_graded.emit("A", {})
	_check("an A rank is not FLAWLESS", not _has("rank_s"))
	GameState.level_graded.emit("S", {})
	_check("FLAWLESS on an S rank", _has("rank_s"))
	var diff0: int = GameState.difficulty
	GameState.difficulty = GameState.Difficulty.HARD
	GameState.level_deaths = 1
	GameState.level_completed.emit()
	_check("a HARD clear with a death is not NO MERCY", not _has("hard_clean"))
	GameState.level_deaths = 0
	GameState.level_completed.emit()
	_check("NO MERCY on a deathless HARD clear", _has("hard_clean"))
	GameState.difficulty = diff0
	GameState.note_hijack()
	_check("FIRMWARE INJECTION on a hijack", _has("hijack"))
	GameState.note_breach()
	_check("SYSADMIN on a network breach", _has("breach"))
	GameState.endings_path = "user://records_ach_probe.cfg"
	for e in ["shutdown", "seat"]:
		GameState.record_ending(e)
	_check("each ending unlocks its own", _has("ending_shutdown") and _has("ending_seat") and not _has("ending_free"))
	_check("not all three yet", not _has("all_endings"))
	GameState.record_ending("free")
	_check("EVERY TIMELINE once all three are seen", _has("ending_free") and _has("all_endings"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://records_ach_probe.cfg"))
	GameState.uprising_closed.emit({"won": false})
	_check("a lost UPRISING run is not a clear", not _has("uprising_clear"))
	GameState.uprising_closed.emit({"won": true})
	_check("UPRISING on a full clear", _has("uprising_clear"))
	GameState.daily_result = {"streak": 2}
	GameState.daily_completed.emit()
	_check("a 2-day streak is not enough", not _has("daily_streak"))
	GameState.daily_result = {"streak": 3}
	GameState.daily_completed.emit()
	_check("CREATURE OF HABIT at a 3-day streak", _has("daily_streak"))
	GameState.daily_result = {}

	# Lifetime counters.
	for i in 9:
		GameState.execution.emit(Vector3.ZERO)
	_check("9 executions are not EXECUTIONER", not _has("executioner"), str(Achievements.progress("executioner")))
	GameState.execution.emit(Vector3.ZERO)
	_check("EXECUTIONER at 10", _has("executioner"))
	for i in 5:
		GameState.bounty_claimed.emit(300)
	_check("BOUNTY HUNTER at 5 bounties", _has("bounty"))
	for i in 498:
		GameState.enemy_killed.emit(100, "DRONE")
	_check("499 kills are not DECOMMISSIONER", not _has("kills_500"), str(Achievements.progress("kills_500")))
	GameState.enemy_killed.emit(100, "DRONE")
	_check("DECOMMISSIONER at 500 kills", _has("kills_500"))

	# 3. Toasts: once each.
	var toasts := Achievements.toasts_shown
	GameState.perfect_dodge.emit()
	_check("an unlocked achievement is never re-announced", Achievements.toasts_shown == toasts)
	_check("every unlock was announced once", toasts == Achievements.unlocked_count(), "%d toasts, %d unlocked" % [toasts, Achievements.unlocked_count()])

	# 4. Persistence.
	var n := Achievements.unlocked_count()
	Achievements.use_file(FILE, false) # reload the same file
	_check("unlocks survive a reload", Achievements.unlocked_count() == n and _has("godlike"), "%d of %d" % [Achievements.unlocked_count(), n])
	_check("all of them unlocked by now", n == Achievements.DEFS.size(), "%d/%d" % [n, Achievements.DEFS.size()])

	# 5. Menu.
	get_tree().change_scene_to_file(GameState.MAIN_MENU)
	await _frames(20)
	var menu: Node = get_tree().current_scene
	var btn := menu.find_child("Achievements", true, false) as Button
	_check("the main menu counts them", btn != null and btn.text.contains("%d/%d" % [n, Achievements.DEFS.size()]), btn.text if btn else "no button")
	if btn:
		btn.pressed.emit()
		await _frames(3)
		var list := menu.find_child("AchievementList", true, false)
		_check("the button opens the list", list != null and list.is_visible_in_tree())

	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
