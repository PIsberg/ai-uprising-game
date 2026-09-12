extends Node
## The main menu warms the first level's dependency chunk while it is on
## screen (GameState.warm_level_cache), so the loading screen's later request
## for the same scene finds it loaded instead of paying ~13 s for the shared
## robot-model chunk in front of the player. Asserts:
##   (1) after the real main menu has run _ready, a threaded load of the first
##       campaign level is already in flight or done (status != INVALID);
##   (2) once it finishes, the loading screen's own request for that path
##       returns LOADED and a usable PackedScene in well under a second.
## Prints the warm load's wall time for the log.
##   godot --headless --path . --audio-driver Dummy res://tests/warm_cache_probe.tscn

const WAIT_S := 120.0

var _fail: Array[String] = []

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GraphicsSettings.needs_auto_quality = false # the menu would otherwise start a benchmark
	GameState.allow_warm_headless = true # the warm-up skips headless runs unless told otherwise
	var first: String = String(GameState.campaign()[0])
	_check(ResourceLoader.load_threaded_get_status(first) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
		"first level is not loaded before the menu appears")
	var t0 := Time.get_ticks_msec()
	var menu: Node = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	var st := ResourceLoader.load_threaded_get_status(first)
	print("after menu _ready: threaded status of %s = %d" % [first, st])
	_check(st != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "menu started warming the first level")
	while ResourceLoader.load_threaded_get_status(first) == ResourceLoader.THREAD_LOAD_IN_PROGRESS \
			and Time.get_ticks_msec() - t0 < WAIT_S * 1000.0:
		await get_tree().process_frame
	print("warm load finished in %.2fs (status %d)" % [(Time.get_ticks_msec() - t0) / 1000.0, ResourceLoader.load_threaded_get_status(first)])
	# What the loading screen does next: its own request + get.
	var t1 := Time.get_ticks_msec()
	var req := ResourceLoader.load_threaded_request(first, "", false)
	var status := ResourceLoader.load_threaded_get_status(first)
	var packed: PackedScene = ResourceLoader.load_threaded_get(first) as PackedScene if status == ResourceLoader.THREAD_LOAD_LOADED else null
	var secs := (Time.get_ticks_msec() - t1) / 1000.0
	print("loading-screen request: err=%d status=%d packed=%s in %.3fs" % [req, status, packed != null, secs])
	_check(req == OK and status == ResourceLoader.THREAD_LOAD_LOADED and packed != null and packed.can_instantiate(),
		"loading screen finds the first level already loaded")
	_check(secs < 1.0, "hand-off to the loading screen takes under a second (%.3fs)" % secs)
	menu.queue_free()
	await get_tree().process_frame
	# Never quit with a threaded load in flight: the loader thread keeps running
	# through engine teardown and spams "Could not preload resource file".
	while ResourceLoader.load_threaded_get_status(first) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit()
