extends Node3D
## Verifies first-time coaching hints for the new mechanics: each fires exactly
## once, the first time its mechanic triggers, and never repeats within a run.

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(1.5).timeout
	GameState.current_state = GameState.State.PLAYING
	GameState.reset_level_stats()
	GameState._taught.clear() # fresh run — no hints shown yet

	var seen: Array = []
	GameState.teach_hint.connect(func(t: String): seen.append(t))

	# Trigger each new mechanic once.
	while GameState.combo < 5: # RAMPAGE tier 1
		GameState.add_kill(100, "HOSTILE")
		GameState.combo_timer = GameState.COMBO_WINDOW
	GameState.try_adrenaline()          # ADRENALINE
	GameState.reward_perfect_dodge()    # PERFECT DODGE
	GameState.reward_execution(Vector3.ZERO) # EXECUTION
	GameState.add_ultimate_charge(1.0)  # OVERLOAD ready
	await get_tree().process_frame

	var keys := ["RAMPAGE", "ADRENALINE", "PERFECT DODGE", "EXECUTION", "OVERLOAD"]
	var got := 0
	for k in keys:
		var found := false
		for t in seen:
			if k in t:
				found = true; break
		if found:
			got += 1
		else:
			print("MISSING hint for %s" % k)
	print("hints fired: %d/%d (total teach emits=%d)" % [got, keys.size(), seen.size()])

	# Re-trigger a couple — must NOT re-teach (idempotent per run).
	var before := seen.size()
	GameState.reward_execution(Vector3.ZERO)
	GameState.reward_perfect_dodge()
	await get_tree().process_frame
	print("after re-trigger: teach emits=%d (expect %d, no repeats)" % [seen.size(), before])
	print("HINTS_PROBE_DONE")
	get_tree().quit()
