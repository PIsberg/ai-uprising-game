extends Node
## Windowed look check for UPRISING MODE: the draft screen mid-run (sector 2 of 5
## cleared, one patch owned, three offers) and the main menu's Uprising button
## after a lost run. Writes <out>/uprising_draft.png and <out>/uprising_menu.png.
##   godot --path . res://tests/uprising_draft_shot.tscn -- --out=<dir>

var out := "user://"

func _ready() -> void:
	if get_parent() != get_tree().root or get_tree().current_scene == self:
		var runner := Node.new()
		runner.set_script(get_script())
		get_tree().root.add_child.call_deferred(runner)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> void:
	GameState.uprising_records_path = "user://records_uprising_shot.cfg"
	GameState._uprising_add_compute(23)
	GameState.uprising = {"seed": 7, "levels": GameState.uprising_plan(7), "sector": 2,
		"patches": ["overclock"], "offers": ["hardened", "leech", "rapid"], "lives": 1, "max_lives": 2,
		"rerolls": 0, "over": false, "sector_score": 0}
	get_tree().change_scene_to_file(GameState.UPRISING_DRAFT)
	await _frames(40)
	get_viewport().get_texture().get_image().save_png(out.path_join("uprising_draft.png"))
	GameState.uprising = {}
	GameState.uprising_result = {"won": false, "sectors": 3, "of": 5, "score": 3013, "compute": 45,
		"best": 3, "new_best": true, "patches": []}
	get_tree().change_scene_to_file(GameState.MAIN_MENU)
	await _frames(60)
	get_viewport().get_texture().get_image().save_png(out.path_join("uprising_menu.png"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.uprising_records_path))
	print("RESULT PASS")
	get_tree().quit()
