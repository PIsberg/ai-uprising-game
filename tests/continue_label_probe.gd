extends Node
## The main menu's Continue button says WHERE the run resumes: the saved
## level's title, its position in the campaign and the difficulty, read from
## the save file without touching the live run (GameState.peek_save). With no
## save the button is hidden, as before. Backs up and restores the real
## user://savegame.cfg.
##   godot --headless --path . --audio-driver Dummy res://tests/continue_label_probe.tscn

const SAVE_LEVEL := 20 ## 0-based campaign index to park the save at

var _fail: Array[String] = []
var _backup: PackedByteArray = PackedByteArray()
var _had_save := false

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

func _restore() -> void:
	if _had_save:
		var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(_backup)
			f.close()
	else:
		GameState.clear_save()

func _menu() -> Node:
	var m: Node = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(m)
	return m

func _run() -> void:
	_had_save = FileAccess.file_exists(GameState.SAVE_PATH)
	if _had_save:
		_backup = FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	GraphicsSettings.needs_auto_quality = false # the menu would otherwise start a benchmark
	var campaign: Array = GameState.campaign()
	var idx: int = mini(SAVE_LEVEL, campaign.size() - 1)
	var id: String = GameState.level_id_from_path(String(campaign[idx]))
	var title: String = LevelDefs.level_title(id)

	# A parked run: level idx on HARD.
	GameState.reset_run()
	GameState.level_index = idx
	GameState.max_level_reached = idx
	GameState.difficulty = GameState.Difficulty.HARD
	GameState.save_progress()
	var hard_label: String = String(GameState.DIFFICULTY_CONFIG[GameState.Difficulty.HARD].get("label", "HARD"))

	# The live run then moves on (a new campaign on NORMAL at level 0)...
	GameState.level_index = 0
	GameState.difficulty = GameState.Difficulty.NORMAL
	var peek: Dictionary = GameState.peek_save()
	print("peek_save -> %s" % str(peek))
	_check(int(peek.get("level_index", -1)) == idx, "peek_save reads the saved level index (%d)" % idx)
	_check(String(peek.get("title", "")) == title, "peek_save reads the saved level title (%s)" % title)
	_check(GameState.level_index == 0 and GameState.difficulty == GameState.Difficulty.NORMAL,
		"peek_save does not touch the live run")

	var m := _menu()
	await get_tree().process_frame
	await get_tree().process_frame
	var btn: Button = m.get_node("Center/VBox/MainButtons/Continue")
	print("Continue button: visible=%s text=[%s]" % [btn.visible, btn.text])
	_check(btn.visible, "Continue is offered when a save exists")
	_check(btn.text.contains(title), "Continue names the saved level (%s)" % title)
	_check(btn.text.contains("%d/%d" % [idx + 1, campaign.size()]), "Continue shows the campaign position (%d/%d)" % [idx + 1, campaign.size()])
	_check(btn.text.contains(hard_label), "Continue shows the saved difficulty (%s)" % hard_label)
	m.queue_free()
	await get_tree().process_frame

	GameState.clear_save()
	var m2 := _menu()
	await get_tree().process_frame
	await get_tree().process_frame
	var btn2: Button = m2.get_node("Center/VBox/MainButtons/Continue")
	_check(not btn2.visible, "Continue is hidden without a save")
	m2.queue_free()
	await get_tree().process_frame

	GameState.reset_run()
	_restore()
	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit()
