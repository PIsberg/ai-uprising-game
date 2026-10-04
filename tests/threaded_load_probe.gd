extends Node
## Every scene the loading screen hands to the player survives the loading
## screen's actual load path: GameState.warm_scripts, then
## ResourceLoader.load_threaded_request with use_sub_threads = false
## (scripts/ui/loading_screen.gd). campaign_smoke loads levels with a plain
## load(). Without the warm-up this probe wedged at IN_PROGRESS in 10 of 94 solo
## runs (#125), so a hang here is that race back, not a slow machine. The
## exported-pack variant of the race is tools/load_race_check.ps1's. The loading
## screen falls back to a blocking change_scene_to_file on THREAD_LOAD_FAILED,
## which would hide a broken resource behind a hitch - this probe does not. It
## also reports the wall time per scene so a load that has crept past a few
## seconds is visible.
##   godot --headless --path . --audio-driver Dummy res://tests/threaded_load_probe.tscn

const TIMEOUT_S := 90.0
const SLOW_S := 8.0 ## report (not fail) loads slower than this, headless

var _fail: Array[String] = []

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

func _scenes() -> Array[String]:
	var out: Array[String] = []
	for p in GameState.campaign():
		out.append(String(p))
	for p in [GameState.INTRO_CUTSCENE, GameState.LEVEL_BRIEFING, GameState.UPRISING_REVEAL,
			GameState.VICTORY_CUTSCENE, GameState.LEVEL_CUSTOM, GameState.LOADING_SCREEN,
			"res://scenes/ui/main_menu.tscn", "res://scenes/ui/campaign_map.tscn"]:
		if String(p) != "" and not out.has(String(p)):
			out.append(String(p))
	return out

func _run() -> void:
	var scenes := _scenes()
	var loaded := 0
	var slow := 0
	for path in scenes:
		if not ResourceLoader.exists(path):
			_check(false, "%s exists" % path)
			continue
		# The game's own path: compile on the main thread, then the threaded load.
		GameState.warm_scripts(path)
		var t0 := Time.get_ticks_msec()
		var req := ResourceLoader.load_threaded_request(path, "", false)
		if req != OK:
			_check(false, "%s: load_threaded_request accepted (err %d)" % [path, req])
			continue
		var status := ResourceLoader.THREAD_LOAD_IN_PROGRESS
		while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
			status = ResourceLoader.load_threaded_get_status(path)
			if Time.get_ticks_msec() - t0 > TIMEOUT_S * 1000.0:
				break
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		var packed: PackedScene = null
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			packed = ResourceLoader.load_threaded_get(path) as PackedScene
		var ok := status == ResourceLoader.THREAD_LOAD_LOADED and packed != null and packed.can_instantiate()
		if ok:
			loaded += 1
		if secs > SLOW_S:
			slow += 1
		print("  %s %-52s %6.2fs  status=%d%s" % ["ok  " if ok else "FAIL", path.trim_prefix("res://"), secs, status, "  SLOW" if secs > SLOW_S else ""])
		if not ok:
			_fail.append(path)
	_check(loaded >= 24, "threaded-loaded a real campaign plus the flow scenes (%d/%d)" % [loaded, scenes.size()])
	print("slow loads (> %.0fs, reported only): %d" % [SLOW_S, slow])
	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit()
