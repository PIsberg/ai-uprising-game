extends Node
## Dev probe: validates the intercepted ROBOT OS patch notes.
## (1) AIDirector.patch_notes() emits changelog lines once the profile has a
##     read (and nothing while calibrating);
## (2) GameState._build_patch_notes folds in security incidents (hijacks) and a
##     standing nemesis; consume_patch_notes hands the batch over exactly once;
## (3) the comic briefing builds the terminal panel when notes are pending.
##   godot --headless --path . res://tests/patchnotes_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ok := true

	# 1. Director changelog from a seeded profile.
	AIDirector.reset_profile()
	var calm: Array = AIDirector.patch_notes()
	for i in 30:
		AIDirector.note_shot()
	for i in 20:
		AIDirector.note_hit(true, Vector3.ZERO)
	var notes: Array = AIDirector.patch_notes()
	var director_ok: bool = calm.is_empty() and notes.size() >= 2 \
		and String(notes[0]).begins_with("+ WARDEN") # precision read -> warden counter
	print("DIRECTOR: calibrating_empty=%s notes=%d first=%s" % [calm.is_empty(), notes.size(), notes[0] if notes.size() > 0 else "-"])
	if not director_ok:
		ok = false

	# 2. GameState folds in hijacks + nemesis; consume is one-shot.
	GameState.level_hijacks = 0
	GameState.note_hijack()
	GameState.note_hijack()
	GameState.nemesis = {"name": "VX-101 'TEST'", "kind": "swift", "scene": "x", "rank": 1}
	GameState.pending_patch_notes = GameState._build_patch_notes()
	var built: Array = GameState.pending_patch_notes
	var has_sec := false
	var has_nem := false
	for n in built:
		if String(n).contains("SECURITY: 2 unit"):
			has_sec = true
		if String(n).contains("VX-101 'TEST' refused decommission"):
			has_nem = true
	var consumed: Array = GameState.consume_patch_notes()
	var once: bool = consumed.size() == built.size() and GameState.consume_patch_notes().is_empty()
	print("BUILD: security=%s nemesis=%s one_shot=%s" % [has_sec, has_nem, once])
	if not (has_sec and has_nem and once):
		ok = false

	# 3. The briefing builds the terminal panel when notes are pending.
	GameState.nemesis = {}
	GameState.pending_patch_notes = ["+ TEST ENTRY ONE", "~ TEST ENTRY TWO"]
	GameState.current_level_path = "res://scenes/levels/level_gpt.tscn"
	var briefing: Node = load("res://scenes/cutscene/level_comic_briefing.tscn").instantiate()
	get_tree().root.add_child(briefing)
	for i in 10:
		await get_tree().process_frame
	var panel_found := false
	for lbl in briefing.find_children("*", "Label", true, false):
		if String((lbl as Label).text).contains("PATCH NOTES"):
			panel_found = true
			break
	var drained: bool = GameState.pending_patch_notes.is_empty()
	print("PANEL: found=%s notes_drained=%s" % [panel_found, drained])
	if not (panel_found and drained):
		ok = false
	briefing.queue_free()

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
