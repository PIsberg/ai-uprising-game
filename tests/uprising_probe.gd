extends Node
## Probe: UPRISING MODE (GameState uprising section, scenes/ui/uprising_draft.tscn).
## Runs from a node under root, so the scene changes it drives do not free it.
## (1) the plan for a seed is fixed: 5 sectors, 4 non-boss in campaign order then
##     a boss; another seed gives another plan;
## (2) start_uprising loads sector 1 and leaves the campaign save untouched;
## (3) clearing it (advance_level) opens the draft with 3 distinct offers;
## (4) a draft button picks its patch: the patch's multipliers apply through the
##     directive getters, sector 2 loads and the score carries over;
## (5) a reroll costs compute and re-rolls the offers; with too little it refuses;
## (6) deaths: UPRISING_LIVES are forgiven, the next ends the run, banks compute
##     and restores the run state it found;
## (7) clearing the last sector banks the full-clear bonus and best_sector;
## (8) the main menu offers an Uprising button.
##   godot --headless --path . --audio-driver Dummy res://tests/uprising_probe.tscn

const RECORDS := "user://records_uprising_probe.cfg"
const SAVE := "user://savegame.cfg"

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	if get_parent() != get_tree().root or get_tree().current_scene == self:
		# Re-home under root so change_scene_* (which frees the current scene) spares us.
		var runner := Node.new()
		runner.set_script(get_script())
		runner.name = "UprisingProbeRunner"
		get_tree().root.add_child.call_deferred(runner)
		return
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _wait_scene(pred: Callable, limit_s: float = 60.0) -> bool:
	var t := 0.0
	while t < limit_s:
		if pred.call():
			return true
		await get_tree().create_timer(0.25, true).timeout
		t += 0.25
	return false

func _save_bytes() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(SAVE) if FileAccess.file_exists(SAVE) else PackedByteArray()

func _player_ready() -> bool:
	return get_tree().get_first_node_in_group("player") != null

func _run() -> void:
	if not GameState.has_method("start_uprising"):
		_check("GameState.start_uprising exists", false)
		print("RESULT FAIL")
		get_tree().quit(1)
		return
	GameState.uprising_records_path = RECORDS
	if FileAccess.file_exists(RECORDS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RECORDS))

	# 1. Plan.
	var a: Array = GameState.uprising_plan(1234)
	var b: Array = GameState.uprising_plan(1234)
	var c: Array = GameState.uprising_plan(98765)
	var camp: Array = GameState.campaign()
	var ids := a.map(func(p): return GameState.level_id_from_path(p))
	print("plan 1234: ", ids)
	_check("same seed, same plan", a == b and a.size() == GameState.UPRISING_SECTORS)
	_check("another seed, another plan", a != c)
	var ordered := true
	for i in range(1, 4):
		ordered = ordered and camp.find(a[i]) > camp.find(a[i - 1])
	_check("four non-boss sectors in campaign order", ordered and not ids.slice(0, 4).any(func(x): return LevelDefs.level_is_boss(x)))
	_check("the last sector is a boss", LevelDefs.level_is_boss(ids[4]))

	# 2. Start.
	var diff_before: int = GameState.difficulty
	GameState.difficulty = GameState.Difficulty.HARD
	var save_before := _save_bytes()
	GameState.start_uprising(1234)
	_check("a run is on", GameState.is_uprising())
	var loaded := await _wait_scene(_player_ready)
	_check("sector 1 loads", loaded and GameState.current_level_path == a[0], GameState.current_level_path)
	_check("campaign save untouched", _save_bytes() == save_before)

	# 3. Clear it.
	GameState.score = 900
	GameState.advance_level()
	var drafted := await _wait_scene(func(): return get_tree().current_scene != null and get_tree().current_scene.has_method("pick"))
	_check("clearing a sector opens the draft", drafted)
	var offers: Array = GameState.uprising["offers"]
	var uniq := {}
	for o in offers:
		uniq[o] = true
	_check("three distinct offers", offers.size() == 3 and uniq.size() == 3, str(offers))

	# 5. Reroll (before picking): refused with no compute, works with enough.
	_check("reroll refused without compute", not GameState.uprising_reroll())
	GameState._uprising_add_compute(GameState.UPRISING_REROLL_COST)
	var before: Array = offers.duplicate()
	_check("reroll with compute", GameState.uprising_reroll())
	_check("reroll spends the compute", int(GameState.uprising_record()["compute"]) == 0)
	_check("reroll changes the offers", GameState.uprising["offers"] != before, str(GameState.uprising["offers"]))

	# 4. Pick through the draft's button.
	var draft: Node = get_tree().current_scene
	var pick_id: String = GameState.uprising["offers"][0]
	var patch: Dictionary = GameState.uprising_patch(pick_id)
	(draft.get("buttons")[0] as Button).pressed.emit()
	_check("the button takes its patch", (GameState.uprising["patches"] as Array) == [pick_id], str(GameState.uprising["patches"]))
	var mult_ok := true
	for key in ["damage", "incoming", "move", "pickup"]:
		var want := float(patch.get(key, 1.0))
		var got: float = GameState.call("directive_%s_mult" % key)
		mult_ok = mult_ok and is_equal_approx(got, want)
	_check("patch multipliers apply through the directive getters", mult_ok, patch["id"])
	loaded = await _wait_scene(func(): return _player_ready() and GameState.current_level_path == a[1])
	_check("sector 2 loads", loaded, GameState.current_level_path)
	_check("score carries over", GameState.score == 900, str(GameState.score))

	# 6. Deaths: lives first, then the run ends and banks.
	for i in GameState.UPRISING_LIVES:
		GameState.on_player_died("probe")
		_check("death %d is forgiven" % (i + 1), GameState.is_uprising() and not GameState.uprising_run_over())
	GameState.on_player_died("probe")
	_check("the next death ends the run", GameState.uprising_run_over())
	var ended := await _wait_scene(func(): return not GameState.is_uprising(), 10.0)
	_check("the run closes after the death beat", ended)
	var res: Dictionary = GameState.uprising_result
	print("result: ", res)
	_check("a lost run banks score + sector compute", int(res.get("compute", -1)) == 900 / 100 + 1 * GameState.UPRISING_SECTOR_COMPUTE)
	_check("run state restored", GameState.difficulty == GameState.Difficulty.HARD)
	await _wait_scene(func(): return get_tree().current_scene != null and get_tree().current_scene.scene_file_path == GameState.MAIN_MENU, 20.0)

	# 8. Menu button.
	var menu: Node = get_tree().current_scene
	var btn: Node = menu.find_child("Uprising", true, false) if menu else null
	_check("main menu offers Uprising", btn is Button and (btn as Button).visible)
	# The script, not the .tscn, writes the result line: a menu script that failed
	# to parse still shows a bare "Uprising" button.
	_check("the button reports the run just lost", btn is Button and (btn as Button).text.contains("+%d" % int(res.get("compute", -1))), (btn as Button).text if btn is Button else "")

	# 7. Full clear.
	GameState.start_uprising(1234)
	await _wait_scene(_player_ready)
	GameState.uprising["sector"] = GameState.UPRISING_SECTORS - 1
	GameState.score = 0
	var total_before: int = int(GameState.uprising_record()["compute"])
	GameState.advance_level()
	await _wait_scene(func(): return not GameState.is_uprising(), 10.0)
	res = GameState.uprising_result
	print("clear: ", res)
	_check("a full clear banks the clear bonus", bool(res.get("won", false)) and int(res.get("compute", 0)) == GameState.UPRISING_SECTORS * GameState.UPRISING_SECTOR_COMPUTE + GameState.UPRISING_CLEAR_COMPUTE)
	var rec: Dictionary = GameState.uprising_record()
	_check("records keep compute and best sector", int(rec["compute"]) == total_before + int(res["compute"]) and int(rec["best"]) == GameState.UPRISING_SECTORS, str(rec))

	# 10. A cleared sector repairs one spent reboot, never past the run's maximum.
	GameState.start_uprising(1234)
	await _wait_scene(_player_ready)
	GameState.uprising["lives"] = 0
	GameState.advance_level()
	_check("a clear repairs a spent reboot", int(GameState.uprising["lives"]) == 1, str(GameState.uprising["lives"]))
	GameState.uprising_pick(String(GameState.uprising["offers"][0]))
	await _wait_scene(_player_ready)
	GameState.uprising["lives"] = int(GameState.uprising["max_lives"])
	GameState.advance_level()
	_check("a clear never repairs past the maximum", int(GameState.uprising["lives"]) == int(GameState.uprising["max_lives"]), str(GameState.uprising["lives"]))
	GameState.abandon_uprising()

	# 11. Locked patches stay out of the pool until lifetime compute reaches them.
	var locked := GameState.UPRISING_PATCHES.filter(func(p): return int(p.get("unlock", 0)) > 0)
	GameState.uprising = {"patches": []}
	var earned_now := int(GameState.uprising_record()["earned"])
	var pool_now: Array = GameState._uprising_pool()
	_check("locked patches wait for lifetime compute", locked.all(func(p): return pool_now.has(String(p["id"])) == (int(p["unlock"]) <= earned_now)), "earned %d pool %s" % [earned_now, pool_now])
	GameState.uprising = {}

	# 9. A sector that has a bespoke story cutscene in the campaign (the sublevel's
	#    UPRISING reveal) still goes through the plain briefing inside a run: the
	#    story beat would land out of order.
	GameState.start_uprising(1234)
	var reveal_lvl := ""
	for lid in GameState.CUTSCENE_FOR_LEVEL:
		reveal_lvl = "res://scenes/levels/level_%s.tscn" % lid
	GameState.go_to_level(reveal_lvl, false)
	_check("a story-cutscene sector takes the plain briefing", GameState.pending_scene == GameState.LEVEL_BRIEFING, GameState.pending_scene)
	GameState.abandon_uprising()

	GameState.difficulty = diff_before
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RECORDS))
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
