extends Node3D
## Fast route-length probe over the levels being given led/gated routes. Prints
## spawn->exit navmesh path length and the detour ratio (walked / crow-flies):
## a higher ratio means the player is led on a longer, weaving path instead of
## walking straight across. Also FAILs loudly if a gate ever closes the route.
## Run: godot --headless --path . --quit-after 100000 res://tests/route_probe.tscn

const IDS := ["01", "sublevel", "uplink", "claude", "gemini", "neon", "titan", "suburb"]

func _ready() -> void:
	var fails := 0
	for id in IDS:
		var path := "res://scenes/levels/level_%s.tscn" % id
		if not ResourceLoader.exists(path):
			print("SKIP %s" % id); continue
		var lvl: Node = (load(path) as PackedScene).instantiate()
		add_child(lvl)
		var pdmg := lvl.find_child("Damageable", true, false)
		if pdmg: pdmg.invulnerable = true
		await get_tree().create_timer(2.2).timeout
		var def: Dictionary = LevelDefs.get_def(id)
		var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
		var exit: Vector3 = def.get("exit", Vector3.ZERO)
		var map := get_world_3d().get_navigation_map()
		var p := NavigationServer3D.map_get_path(map, spawn, exit, true)
		var verdict := "NO-PATH"
		if p.size() >= 2:
			var endp := p[p.size() - 1]
			var gap := Vector2(endp.x - exit.x, endp.z - exit.z).length()
			var walked := 0.0
			for i in range(1, p.size()):
				walked += p[i].distance_to(p[i - 1])
			var crow := spawn.distance_to(exit)
			var detour := walked / maxf(crow, 0.001)
			verdict = "PASS gap=%.1f len=%.0f crow=%.0f x%.2f" % [gap, walked, crow, detour] if gap < 5.0 else "FAIL gap=%.1f" % gap
		if not verdict.begins_with("PASS"): fails += 1
		print("ROUTE %s: %s" % [id, verdict])
		lvl.queue_free()
		await get_tree().process_frame
	print("ROUTE_PROBE_DONE fails=%d" % fails)
	get_tree().quit()
