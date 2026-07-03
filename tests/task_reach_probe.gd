extends Node
## Loads level 1 for real and verifies every authored task position resolves
## to a spot that is clear of solid geometry and near the navmesh — i.e. no
## more objectives buried inside buildings/platforms.
##   godot --headless --path . --audio-driver Dummy res://tests/task_reach_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ps: PackedScene = load("res://scenes/levels/level_01.tscn")
	var lvl := ps.instantiate()
	get_tree().root.add_child(lvl)
	await get_tree().create_timer(2.0).timeout # build + deferred navmesh bake
	var def: Dictionary = LevelDefs.get_def("01")
	var ok := true
	for t in def.get("tasks", []):
		if not t.has("pos"):
			continue
		var authored: Vector3 = t["pos"]
		var resolved: Vector3 = lvl._reachable_task_pos(authored)
		var clear: bool = lvl._point_clear(lvl.get_world_3d().direct_space_state, resolved)
		var nav := NavigationServer3D.map_get_closest_point(lvl.get_world_3d().navigation_map, resolved)
		var nav_d := Vector2(nav.x - resolved.x, nav.z - resolved.z).length()
		var moved := authored.distance_to(resolved) > 0.01
		print("%s  authored=%s resolved=%s moved=%s clear=%s nav_d=%.2f" % [
			t.get("type", "?"), authored, resolved, moved, clear, nav_d])
		if not clear or nav_d > 1.6:
			ok = false
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
