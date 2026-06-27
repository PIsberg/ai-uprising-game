extends Node
## Dev probe: validates every weapon in the arsenal has sane WeaponData — guards
## against a .tres regression silently shipping a broken gun (the Weapon Codex and
## balance both rely on these). Loads each weapon scene WITHOUT entering the tree.
##   godot --headless --path . res://tests/weapon_stats_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ok := true
	var n := 0
	for path in GameState.WEAPON_ORDER:
		var ps := load(path) as PackedScene
		if ps == null:
			print("MISSING scene: %s" % path); ok = false; continue
		var inst := ps.instantiate()
		var d := inst.get("data") as WeaponData
		inst.free()
		if d == null:
			print("NO DATA: %s" % path); ok = false; continue
		n += 1
		var bad: Array = []
		if String(d.display_name).strip_edges() == "": bad.append("name")
		if d.damage <= 0.0: bad.append("damage")
		if d.fire_rate <= 0.0: bad.append("fire_rate")
		if d.mag_size <= 0: bad.append("mag_size")
		if d.range_m <= 0.0: bad.append("range_m")
		if d.headshot_mult <= 0.0: bad.append("headshot_mult")
		if not bad.is_empty():
			print("BAD %s (%s): %s" % [d.display_name, path.get_file(), ", ".join(bad)])
			ok = false
	print("WEAPONS validated=%d / %d" % [n, GameState.WEAPON_ORDER.size()])
	if n != GameState.WEAPON_ORDER.size():
		ok = false
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
