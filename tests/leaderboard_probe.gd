extends Node
## Personal leaderboard: every campaign level keeps your top BOARD_SIZE runs by
## performance points (the 0-100 score behind the letter grade).
##   - record_run keeps the board sorted best first, cut at BOARD_SIZE, and
##     returns the run's 1-based place, or 0 when it misses the board;
##   - a tie places the new run below the older one (the record stands);
##   - the board survives a reload from records.cfg (path redirected here);
##   - grade_level enters a campaign clear and reports points and place in its
##     stats; an UPRISING sector, a Daily Op and a level with no id are not
##     entered (their patches and directives are not the campaign's game);
##   - the debrief names the place and the board's top score, and the campaign
##     map's sector intel lists the board.
##   godot --headless --path . --audio-driver Dummy res://tests/leaderboard_probe.tscn

const LID := "02" ## level_id_from_path("res://scenes/levels/level_02.tscn")
const PATH := "user://leaderboard_probe_records.cfg"

var _fail: Array[String] = []

func _check(cond: bool, label: String, detail: String = "") -> void:
	print(("  ok   " if cond else "  FAIL ") + label + ("  (" + detail + ")" if detail != "" else ""))
	if not cond:
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var orig_path: String = GameState.board_path
	var orig_boards: Dictionary = GameState.level_boards.duplicate(true)
	var orig_level: String = GameState.current_level_path
	var orig_bests: Dictionary = GameState.level_bests.duplicate()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	GameState.board_path = PATH
	GameState.level_boards.clear()

	# Board order, cut and places.
	var places: Array = []
	for pts in [60.0, 80.0, 70.0, 90.0, 50.0, 40.0, 85.0]:
		places.append(GameState.record_run(LID, {"points": pts, "grade": "B", "time": 100.0}))
	var board: Array = GameState.level_board(LID)
	var pts_list := board.map(func(r: Dictionary) -> float: return float(r["points"]))
	_check(pts_list == [90.0, 85.0, 80.0, 70.0, 60.0], "board keeps the top %d, best first" % GameState.BOARD_SIZE, str(pts_list))
	_check(places == [1, 1, 2, 1, 5, 0, 2], "each run reports its place at entry, 0 off the board", str(places))
	var tie := GameState.record_run(LID, {"points": 80.0, "grade": "A", "time": 50.0})
	board = GameState.level_board(LID)
	_check(tie == 4 and str(board[2]["grade"]) == "B" and str(board[3]["grade"]) == "A",
			"a tie goes below the older run", "place %d" % tie)
	_check(board[0].has("date") and board[0].has("diff"), "entries carry the date and difficulty", str(board[0]))

	# Persistence.
	var saved: Array = GameState.level_board(LID)
	GameState.level_boards.clear()
	GameState._load_level_boards()
	_check(GameState.level_board(LID) == saved, "the board reloads from records.cfg")
	_check(GameState.level_board("03").is_empty(), "another level has its own (empty) board")

	# grade_level enters campaign clears only.
	GameState.level_boards.clear()
	GameState.current_level_path = "res://scenes/levels/level_%s.tscn" % LID
	var r := _grade()
	var st: Dictionary = r["stats"]
	_check(int(st.get("board_place", -1)) == 1 and float(st.get("points", -1.0)) > 0.0,
			"a campaign clear is entered and its stats carry points and place",
			"place %s points %s" % [st.get("board_place"), st.get("points")])
	_check(GameState.level_board(LID).size() == 1, "the clear is on the board", str(GameState.level_board(LID)))
	for i in GameState.BOARD_SIZE:
		GameState.record_run(LID, {"points": 99.0, "grade": "S", "time": 60.0})
	r = _grade()
	_check(int(r["stats"].get("board_place", -1)) == 0 and float(r["stats"].get("board_top", 0.0)) == 99.0,
			"a campaign clear off the board reports place 0 and the top to beat", str(r["stats"].get("board_place")))
	GameState.level_boards.clear()
	GameState.record_run(LID, {"points": float(st["points"]), "grade": "B", "time": 100.0})
	GameState.uprising = {"sector": 0, "levels": [GameState.current_level_path], "patches": []}
	r = _grade()
	_check(not r["stats"].has("board_place") and GameState.level_board(LID).size() == 1,
			"an UPRISING sector is not entered")
	GameState.uprising = {}
	GameState.daily_op = {"level": GameState.current_level_path}
	r = _grade()
	_check(not r["stats"].has("board_place") and GameState.level_board(LID).size() == 1,
			"a Daily Op is not entered")
	GameState.daily_op = {}
	GameState.current_level_path = ""
	r = _grade()
	_check(not r["stats"].has("board_place"), "a level with no id is not entered")

	# Debrief line.
	var top := float(GameState.level_board(LID)[0]["points"])
	var hud := preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(hud)
	await get_tree().process_frame
	var line: String = hud.board_line({"points": 77.4, "board_place": 2, "board_top": 91.0})
	_check(line.contains("77") and line.contains("#2") and line.contains("91"), "debrief names points, place and top", line)
	line = hud.board_line({"points": 95.0, "board_place": 1, "board_top": 95.0})
	_check(line.contains("#1") and line.contains(tr("PERSONAL BEST")), "a first place is a personal best", line)
	line = hud.board_line({"points": 20.0, "board_place": 0, "board_top": top})
	_check(not line.contains("#") and line.contains("%d" % roundi(top)), "off the board shows only the top to beat", line)
	_check(hud.board_line({}) == "", "no board stats, no line")
	var map := preload("res://scripts/ui/campaign_map.gd")
	var txt: String = map.board_text([{"points": 91.2, "grade": "S", "diff": "HARD", "time": 154.0},
			{"points": 70.0, "grade": "B", "diff": "NORMAL", "time": 61.0}])
	_check(txt.contains("#1  91  S  HARD  02:34") and txt.contains("#2  70  B  NORMAL  01:01"),
			"the campaign map's intel lists the board, best first", txt.replace("
", " | "))
	_check(map.board_text([]) == "", "an empty board adds nothing to the intel")
	hud.queue_free()

	GameState.board_path = orig_path
	GameState.level_boards = orig_boards
	GameState.current_level_path = orig_level
	GameState.level_bests = orig_bests
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("RESULT %s" % ("PASS" if _fail.is_empty() else "FAIL"))
	get_tree().quit(0 if _fail.is_empty() else 1)

## Grade a fixed decent run (no par in the mix: elapsed is far past par).
func _grade() -> Dictionary:
	GameState.stat_shots = 100
	GameState.stat_hits = 70
	GameState.max_combo = 6
	GameState.stat_damage_taken = 80.0
	GameState.level_start_ms = Time.get_ticks_msec() - 3_600_000
	return GameState.grade_level()
