extends Node
## Probe: the branching ending (StoryArc.ENDINGS, scripts/cutscene/ending_choice.gd).
## (1) a run counts its hijacks and breaches (GameState.note_hijack / note_breach),
##     start_campaign zeroes them and a save/load round trip keeps them;
## (2) SHUT IT DOWN is always open; TAKE ITS SEAT opens at ENDING_HIJACKS hijacks in
##     the run and SET IT FREE at ENDING_BREACHES breaches;
## (3) the choice screen offers all three, a locked one disabled and naming what it
##     needs and how far the run got; pressing an open one emits `chosen`, records
##     the ending as seen (persisted) and marks it SEEN next time;
## (4) each ending's broadcast is its own: the transmission for an ending carries
##     that ending's header and lines, and the three differ.
##   godot --headless --path . --audio-driver Dummy res://tests/ending_choice_probe.tscn

const RECORDS := "user://records_ending_probe.cfg"
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> void:
	GameState.endings_path = RECORDS
	if FileAccess.file_exists(RECORDS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RECORDS))
	var save_before := FileAccess.get_file_as_bytes(GameState.SAVE_PATH) if GameState.has_save() else PackedByteArray()

	# 1. Counting.
	GameState.run_hijacks = 0
	GameState.run_breaches = 0
	GameState.note_hijack()
	GameState.note_breach()
	GameState.note_breach()
	_check("hijacks and breaches are counted for the run", GameState.run_hijacks == 1 and GameState.run_breaches == 2)
	GameState.save_progress()
	GameState.run_hijacks = 0
	GameState.run_breaches = 0
	GameState.load_progress()
	_check("a save/load round trip keeps them", GameState.run_hijacks == 1 and GameState.run_breaches == 2, "%d %d" % [GameState.run_hijacks, GameState.run_breaches])

	# 2. Unlocks.
	_check("SHUT IT DOWN is always open", StoryArc.ending_open("shutdown", 0, 0))
	_check("TAKE ITS SEAT waits for hijacks", not StoryArc.ending_open("seat", StoryArc.ENDING_HIJACKS - 1, 99) and StoryArc.ending_open("seat", StoryArc.ENDING_HIJACKS, 0))
	_check("SET IT FREE waits for breaches", not StoryArc.ending_open("free", 99, StoryArc.ENDING_BREACHES - 1) and StoryArc.ending_open("free", 0, StoryArc.ENDING_BREACHES))

	# 3. The choice screen.
	GameState.run_hijacks = StoryArc.ENDING_HIJACKS
	GameState.run_breaches = 1
	var ch := EndingChoice.new()
	add_child(ch)
	await _frames(3)
	var bs: Dictionary = ch.buttons
	_check("three endings offered", bs.size() == 3, str(bs.keys()))
	_check("open endings are pressable", not (bs["shutdown"] as Button).disabled and not (bs["seat"] as Button).disabled)
	var free_b := bs["free"] as Button
	_check("a locked ending is disabled and says what it needs", free_b.disabled and ch.button_text("free").contains("%d/%d" % [1, StoryArc.ENDING_BREACHES]), ch.button_text("free"))
	var got := [""]
	ch.chosen.connect(func(id: String) -> void: got[0] = id)
	(bs["seat"] as Button).pressed.emit()
	await _frames(2)
	_check("pressing an ending chooses it", got[0] == "seat")
	_check("the ending is recorded as seen", GameState.endings_seen().has("seat"))
	var cf := ConfigFile.new()
	cf.load(RECORDS)
	_check("and persisted", (cf.get_value("endings", "seen", []) as Array).has("seat"))
	ch.queue_free()
	var ch2 := EndingChoice.new()
	add_child(ch2)
	await _frames(3)
	_check("a seen ending is marked next time", ch2.button_text("seat").contains(tr("SEEN")) and not ch2.button_text("shutdown").contains(tr("SEEN")))
	ch2.queue_free()

	# 4. Each ending's own broadcast.
	var heads := {}
	var firsts := {}
	for id in StoryArc.ENDINGS:
		var x := EndingChoice.transmission_for(id)
		var want: Dictionary = StoryArc.ENDINGS[id]
		_check("%s broadcast carries its lines" % id, x.header_text == String(want["header"]) and Array(x.lines) == Array(want["lines"]))
		heads[x.header_text] = true
		firsts[Array(x.lines)[1]] = true
		x.free()
	_check("the three broadcasts differ", heads.size() == 3 and firsts.size() == 3)

	if save_before.is_empty():
		GameState.clear_save()
	else:
		var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(save_before)
		f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RECORDS))
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
