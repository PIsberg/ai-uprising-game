extends Node
## Probe: COMBAT DIRECTIVES roll where a level is genuinely new, and only there.
## Drives GameState's level-entry calls without loading scenes (pending_scene is
## set, the change is never awaited), the way the game makes them:
## (1) entering a non-boss campaign level the normal way, go_to_level (the
##     briefing then calls load_level(path, false)), rolls a directive about
##     DIRECTIVE_CHANCE of the time: before the fix 0 of 200 entries rolled one,
##     because only load_level(path, reset=true) rolled and the briefing passes false;
## (2) a boss level never rolls one;
## (3) TRY AGAIN without a checkpoint (load_level(path), reset=true, same level)
##     keeps the directive the level started with instead of rerolling it;
## (4) Continue (continue_campaign) rolls one for the level it resumes.
##   godot --headless --path . --audio-driver Dummy res://tests/directive_roll_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	if get_parent() != get_tree().root or get_tree().current_scene == self:
		# Re-home under root: the level-entry calls change scenes, which frees the current one.
		var runner := Node.new()
		runner.set_script(get_script())
		get_tree().root.add_child.call_deferred(runner)
		return
	_run.call_deferred()

## The calls the campaign makes to enter `path`: go_to_level, then the briefing's load_level.
func _enter(path: String) -> void:
	GameState.go_to_level(path, false)
	GameState.load_level(path, false)

func _run() -> void:
	var camp: Array = GameState.campaign()
	var normal := ""
	var boss := ""
	for p in camp.slice(1):
		var lid := GameState.level_id_from_path(String(p))
		if normal == "" and not LevelDefs.level_is_boss(lid):
			normal = String(p)
		if boss == "" and LevelDefs.level_is_boss(lid):
			boss = String(p)
	var save_bytes := FileAccess.get_file_as_bytes(GameState.SAVE_PATH) if GameState.has_save() else PackedByteArray()

	# 1. Normal entry rolls at about DIRECTIVE_CHANCE.
	var n := 200
	var hits := 0
	for i in n:
		_enter(normal)
		if GameState.directive_id != "":
			hits += 1
	var want := GameState.DIRECTIVE_CHANCE * n
	_check("a campaign level entered normally rolls a directive ~%.0f%% of the time" % (GameState.DIRECTIVE_CHANCE * 100.0),
		absf(hits - want) < 0.15 * n, "%d/%d" % [hits, n])

	# 2. Bosses stay pure.
	var boss_hits := 0
	for i in 40:
		_enter(boss)
		if GameState.directive_id != "":
			boss_hits += 1
	_check("a boss level never rolls one", boss_hits == 0, "%d/40" % boss_hits)

	# 3. TRY AGAIN keeps the level's directive.
	var kept := 0
	var tries := 0
	for i in 60:
		_enter(normal)
		var had := GameState.directive_id
		if had == "":
			continue
		tries += 1
		GameState.clear_checkpoint()
		GameState.load_level(normal) # the HUD's TRY AGAIN with no checkpoint
		if GameState.directive_id == had:
			kept += 1
	_check("TRY AGAIN keeps the level's directive", tries > 10 and kept == tries, "%d/%d" % [kept, tries])

	# 4. Continue rolls for the resumed level.
	var cont_hits := 0
	for i in 60:
		GameState.directive = {}
		GameState.directive_id = ""
		GameState.level_index = camp.find(normal)
		GameState.save_progress()
		GameState.continue_campaign()
		if GameState.directive_id != "":
			cont_hits += 1
	_check("Continue rolls a directive for the level it resumes", cont_hits > 20, "%d/60" % cont_hits)

	# Leave the player's campaign save as it was.
	if save_bytes.is_empty():
		GameState.clear_save()
	else:
		var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(save_bytes)
		f.close()
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
