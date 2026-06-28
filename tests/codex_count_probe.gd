extends Node
## Dev probe: simulates the warp cheat's discover_all_enemies() and counts how many
## enemies the Enemy Codex would then show (discovered AND has a codex entry).
##   godot --headless --path . res://tests/codex_count_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.discover_all_enemies()
	var total := EnemyCodex.ORDER.size()
	var shown := 0
	var missing: Array = []
	for t in EnemyCodex.ORDER:
		if GameState.is_enemy_discovered(t) and EnemyCodex.has(t):
			shown += 1
		else:
			missing.append(t)
	print("CODEX would show %d / %d" % [shown, total])
	if not missing.is_empty():
		print("MISSING: ", ", ".join(PackedStringArray(missing)))
	print("RESULT ", "PASS" if shown == total else "FAIL")
	get_tree().quit()
