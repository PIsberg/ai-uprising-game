extends Node
## Windowed look check for ACHIEVEMENTS: the main menu with the list open (a few
## unlocked, counters in progress) and an unlock toast in the corner.
## Writes <out>/achievements.png.
##   godot --path . res://tests/achievements_shot.tscn -- --out=<dir>

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
	Achievements.use_file("user://achievements_shot.cfg", true)
	for i in 3:
		GameState.execution.emit(Vector3.ZERO)
	GameState.enemy_killed.emit(100, "DRONE")
	GameState.perfect_dodge.emit()
	GameState.note_breach()
	get_tree().change_scene_to_file(GameState.MAIN_MENU)
	await _frames(30)
	(get_tree().current_scene.find_child("Achievements", true, false) as Button).pressed.emit()
	GameState.rampage_changed.emit(3, "GODLIKE") # a fresh toast over the list
	await _frames(20)
	get_viewport().get_texture().get_image().save_png(out.path_join("achievements.png"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://achievements_shot.cfg"))
	print("RESULT PASS")
	get_tree().quit()
