extends Node
## Headless check of the simplified level-01 objective: exactly ONE checklist
## task (the gate lever), spawned live (not staged), and completing it counts
## as all-tasks-done so the exit portal unseals.
##   godot --headless --path . --audio-driver Dummy res://tests/level01_task_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var lvl := (load("res://scenes/levels/level_01.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(lvl)
	await get_tree().create_timer(2.5).timeout
	var fails := 0
	var tasks: Array = GameState.level_tasks
	print("tasks: ", tasks)
	if tasks.size() != 1:
		print("FAIL: expected 1 task, got %d" % tasks.size())
		fails += 1
	if not GameState.has_task("gates"):
		print("FAIL: no 'gates' task registered")
		fails += 1
	var console := lvl.find_child("HoldConsole*", true, false)
	if console == null:
		# Code-built nodes may keep the default class name.
		for c in lvl.get_children():
			if c is HoldConsole:
				console = c
				break
	if console == null:
		print("FAIL: gate lever console not spawned")
		fails += 1
	else:
		print("console at ", (console as Node3D).global_position)
	GameState.complete_task("gates")
	if not GameState.all_tasks_done():
		print("FAIL: level not clear after opening the gate")
		fails += 1
	print("RESULT ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(fails)
