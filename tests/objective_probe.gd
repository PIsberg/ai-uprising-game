extends Node
## Dev probe: validates the reworked objectives at runtime. Builds the frostbreak
## level (kill_all + assassinate HVT) and the neon level (kill_all + hold_zone),
## checks the tasks register and the HVT both spawns and completes on death, and
## also checks level 1 registers its keycard task. Prints PASS/FAIL, then quits.
##   godot --path . --headless res://tests/objective_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ok := true

	# --- Frostbreak: assassinate HVT ---
	var lvl: Node = load("res://scenes/levels/level_frostbreak.tscn").instantiate()
	get_tree().root.add_child(lvl)
	await _wait(1.5)
	var hvts := get_tree().get_nodes_in_group("hvt")
	var has_hvt_task := _has_task("hvt")
	print("FROSTBREAK hvt_nodes=%d hvt_task=%s tasks=%d" % [hvts.size(), has_hvt_task, GameState.level_tasks.size()])
	if hvts.size() != 1 or not has_hvt_task:
		ok = false
	else:
		var hvt = hvts[0]
		if hvt.hp == null:
			ok = false
		else:
			hvt.hp.apply_damage(999999.0, null) # execute the target
			await _wait(0.4)
			var done := GameState.is_task_done("hvt")
			print("FROSTBREAK hvt_task_done_on_death=%s" % done)
			if not done:
				ok = false
	lvl.queue_free()
	await _wait(0.3)

	# --- Neon: hold_zone ---
	var lvl2: Node = load("res://scenes/levels/level_neon.tscn").instantiate()
	get_tree().root.add_child(lvl2)
	await _wait(1.3)
	var has_hold := _has_task("hold")
	print("NEON hold_task=%s tasks=%d" % [has_hold, GameState.level_tasks.size()])
	if not has_hold:
		ok = false
	lvl2.queue_free()
	await _wait(0.3)

	# --- Level 1: keycard task ---
	var lvl3: Node = load("res://scenes/levels/level_01.tscn").instantiate()
	get_tree().root.add_child(lvl3)
	await _wait(1.3)
	var has_key := _has_task("key")
	var keycards := get_tree().get_nodes_in_group("keycard")
	print("LEVEL01 key_task=%s keycard_nodes=%d" % [has_key, keycards.size()])
	if not has_key or keycards.is_empty():
		ok = false

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _has_task(id: String) -> bool:
	for t in GameState.level_tasks:
		if t["id"] == id:
			return true
	return false

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
