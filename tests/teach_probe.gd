extends Node
## Dev probe: checks the first-encounter teaching system — each hint fires once,
## repeats are suppressed, and a new run re-arms them.
##   godot --headless --path . res://tests/teach_probe.tscn

var _hits: Array = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.teach_hint.connect(func(t): _hits.append(t))
	GameState.reset_run()
	var ok := true

	GameState.teach_elite("warden")
	GameState.teach_elite("warden")   # repeat -> suppressed
	GameState.teach_elite("swift")
	GameState.teach_once("hazard_in", "in the sea")
	GameState.teach_once("hazard_in", "in the sea") # repeat -> suppressed
	GameState.teach_once("unknown", "")             # empty text -> no hint
	# Expect exactly 3 distinct hints (warden, swift, hazard).
	print("after first run: %d hints (expect 3)" % _hits.size())
	if _hits.size() != 3:
		ok = false

	# A fresh run re-arms the hints.
	GameState.reset_run()
	GameState.teach_elite("warden")
	print("after reset: %d total (expect 4)" % _hits.size())
	if _hits.size() != 4:
		ok = false

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
