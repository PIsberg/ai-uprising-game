extends Node
## Dev probe: on the lava arena, force-kills flyers out over the open sea and
## asserts their supply drops are relocated onto a walkway (never left stranded at
## floor level inside the hazard, where they'd be unreachable).
##   godot --headless --path . res://tests/loot_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var lvl: Node = load("res://scenes/levels/level_lava_world.tscn").instantiate()
	get_tree().root.add_child(lvl)
	await _wait(1.6)

	# Kill every flyer out over open sea with a guaranteed drop.
	var killed := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D) or e.get("hp") == null:
			continue
		e.set("drop_chance", 1.0)       # guarantee a drop for the test
		(e as Node3D).global_position = Vector3(5, 3, -12) # open sea, no platform below
		e.hp.apply_damage(999999.0, null)
		killed += 1
	await _wait(1.0)

	var pickups := _find_pickups(lvl)
	var stranded := 0
	for pk in pickups:
		if pk.global_position.y < 1.0 and _in_hazard(pk.global_position):
			stranded += 1
	print("LOOT killed=%d drops=%d stranded_in_sea=%d" % [killed, pickups.size(), stranded])
	var ok := pickups.size() > 0 and stranded == 0
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _find_pickups(n: Node, out: Array = []) -> Array:
	if n is Node3D and String(n.scene_file_path).contains("/pickups/"):
		out.append(n)
	for c in n.get_children():
		_find_pickups(c, out)
	return out

func _in_hazard(p: Vector3) -> bool:
	for h in get_tree().get_nodes_in_group("hazard"):
		if h is LavaHazard:
			var hp: Vector3 = (h as Node3D).global_position
			var s: Vector2 = (h as LavaHazard).size
			if absf(p.x - hp.x) <= s.x * 0.5 and absf(p.z - hp.z) <= s.y * 0.5:
				return true
	return false

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
