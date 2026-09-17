extends Node
## Level 1 reaches the player through the loading screen, two ways: the new-run
## path (main menu warms level 1 in the background, the loading screen joins that
## load) and, with `-- direct`, a cold loading-screen request like every un-warmed
## level, cutscene and custom level gets. Windowed only, and one run proves little:
## use tools/load_race_check.ps1, which cold-starts it repeatedly against an
## exported pack. With use_sub_threads the direct path hung 4 of 12 cold starts
## (scripts compiling on worker threads failed their preload() of resources another
## worker was loading), and sub-threads on in the warm-up alone froze the menu path
## 7 of 12; source runs and headless never showed either.
##   godot --path . --audio-driver Dummy res://tests/loading_screen_deploy_probe.tscn [-- direct]

const LEVEL := "res://scenes/levels/level_01.tscn"
const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const MENU_DWELL_MS := 1500
const TIMEOUT_MS := 20000

class Watcher extends Node:
	var phase := "menu"
	var t0 := 0

	func _process(_delta: float) -> void:
		if phase == "direct":
			_enter_loading_screen()
			return
		var el := Time.get_ticks_msec() - t0
		var cur := get_tree().current_scene
		var on := cur.scene_file_path if is_instance_valid(cur) else "<no scene>"
		if phase == "menu":
			if on == MAIN_MENU and el >= MENU_DWELL_MS:
				var warm := ResourceLoader.load_threaded_get_status(LEVEL)
				print("  ok   main menu up; warm-up status of level_01 = %d" % warm)
				_enter_loading_screen()
			elif el > TIMEOUT_MS:
				_finish(false, "main menu not current after %.0fs; on %s" % [el / 1000.0, on])
		elif on == LEVEL:
			_finish(true, "%s is the current scene %.2fs after the loading screen took over" % [LEVEL, el / 1000.0])
		elif el > TIMEOUT_MS:
			_finish(false, "%s not current after %.0fs; still on %s" % [LEVEL, el / 1000.0, on])

	func _enter_loading_screen() -> void:
		# GameState._enter_level_scene's route, minus load_level's
		# save_progress(), which would overwrite the real savegame.cfg.
		GameState.current_level_path = LEVEL
		GameState.pending_scene = LEVEL
		get_tree().change_scene_to_file(GameState.LOADING_SCREEN)
		phase = "load"
		t0 = Time.get_ticks_msec()

	func _finish(ok: bool, msg: String) -> void:
		print("  %s %s" % ["ok  " if ok else "FAIL", msg])
		print("RESULT ", "PASS" if ok else "FAIL")
		set_process(false)
		get_tree().quit(0 if ok else 1)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GraphicsSettings.needs_auto_quality = false # the menu would otherwise start a benchmark
	# change_scene frees this probe, so the watcher lives directly under root.
	var w := Watcher.new()
	w.t0 = Time.get_ticks_msec()
	w.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(w)
	if "direct" in OS.get_cmdline_user_args():
		w.phase = "direct"
	else:
		get_tree().change_scene_to_file(MAIN_MENU)
