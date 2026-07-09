extends Node3D
## Does a level's hand-placed "pickups" actually exist in the built level?
## LevelBuilder._build_pickups reads p["kind"], but every campaign def authors
## p["type"] — this prints what the def asks for vs what got instantiated.

func _ready() -> void:
	var def: Dictionary = LevelDefs.get_def("gpt")
	var want: Array = def.get("pickups", [])
	print("def pickups: ", want.size(), "  first: ", want[0] if want.size() > 0 else "-")
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(1.5).timeout
	# Count instantiated pickup nodes by their scene's root script/filename.
	var hist := {}
	for n in _walk(lvl):
		var f := String(n.scene_file_path)
		# Roots only — a health pack's syringe mesh also lives under an assets
		# path containing "pickups" and would double-count.
		if f.begins_with("res://scenes/pickups/"):
			var k := f.get_file()
			hist[k] = int(hist.get(k, 0)) + 1
	print("instantiated pickups: ", hist)
	var supply := 0
	for k in hist:
		if not String(k).begins_with("weapon"):
			supply += int(hist[k])
	print("supply pickups: %d (def wants %d)" % [supply, want.size()])
	var ok := supply >= want.size()

	# The purge's mid-hold supply vent runs through a different path
	# (_vent_supplies, driven by SurviveTimer.wave_due) — exercise it for real
	# rather than trusting the def, since a wave only fires late in the level.
	lvl.call("_vent_supplies", [
		{"type": "ammo", "pos": Vector3(0, 0, -7)},
		{"type": "health", "pos": Vector3(0, 0, 7)},
	])
	await get_tree().process_frame
	var after := 0
	for n in _walk(lvl):
		if String(n.scene_file_path).begins_with("res://scenes/pickups/"):
			after += 1
	var vented := after - (supply + int(hist.get("weapon_pickup.tscn", 0)))
	print("vented supplies: %d (expect 2)" % vented)
	ok = ok and vented == 2
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
