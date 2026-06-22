extends Node
## Headless Phase-0 test: serialize a def, reload it, build level_custom from it,
## and assert the round-trip + custom build + pickups work. Prints PASS/FAIL.
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var def := {
		"name": "Phase0 Test", "objective": "verify", "open_sky": true,
		"floor_size": Vector2(40, 40), "floor_color": Color(0.2, 0.2, 0.22),
		"spawn": Vector3(-10, 1, -10), "exit": Vector3(10, 1.5, 10),
		"env": {"sky_top": Color(0.1, 0.1, 0.15)},
		"enemies": [{"type": "android", "pos": Vector3(0, 0, 0)},
			{"type": "drone", "pos": Vector3(4, 0, 2)}],
		"props": [{"type": "crate", "pos": Vector3(-2, 0, 2)}],
		"pickups": [{"kind": "health", "pos": Vector3(2, 0, -2)},
			{"kind": "overclock", "pos": Vector3(-3, 0, 3)}],
		"weapon": {"scene": "res://scenes/weapons/rifle.tscn", "pos": Vector3(0, 0, -4)},
		"tasks": [{"type": "kill_all"}],
	}
	var path := CustomLevels.save_def(def, "_phase0")
	print("SAVED ", path)
	var back := CustomLevels.load_def(path)
	var ok := true
	ok = ok and back.get("name") == "Phase0 Test"
	ok = ok and back.get("spawn") == Vector3(-10, 1, -10)        # Vector3 survived
	ok = ok and back.get("floor_color") == Color(0.2, 0.2, 0.22) # Color survived
	ok = ok and (back.get("enemies", []) as Array).size() == 2
	print("ROUNDTRIP ", "ok" if ok else "FAIL")
	# Build it.
	GameState.custom_level_path = path
	var lvl: PackedScene = load("res://scenes/levels/level_custom.tscn")
	var inst := lvl.instantiate()
	get_tree().root.add_child(inst)
	for i in 30:
		await get_tree().process_frame
	var enemies := get_tree().get_nodes_in_group("enemy").size()
	var pickups := 0
	for n in inst.get_children():
		if n is Area3D and (n.is_in_group("pickup") or "Health" in n.name or "Overclock" in n.name or "pickup" in n.name.to_lower()):
			pickups += 1
	print("BUILT enemies=", enemies, " pickups>=", pickups)
	var pass_all := ok and enemies >= 2
	print("PHASE0 ", "PASS" if pass_all else "FAIL")
	get_tree().quit()
