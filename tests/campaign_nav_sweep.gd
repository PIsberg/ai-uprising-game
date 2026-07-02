extends Node3D
## Full-campaign softlock guard: builds every LevelDefs-driven level (skips the
## hand-authored level_01) and confirms the exit is navmesh-reachable from the
## spawn. Boss/objective levels with no authored "exit" are skipped (nothing to
## check). Prints one PASS/FAIL line per level; no screenshots (headless-safe).
## Run: godot --headless --path . --quit-after 4000 res://tests/campaign_nav_sweep.tscn

const IDS := [
	"01", "gpt", "gemini", "mistral", "suburb", "suburb_boss",
	"claude", "grok", "uplink", "overseer",
	"alien", "assembly", "sublevel", "frostbreak", "water_world", "desert",
	"neon", "crucible", "lava_world", "titan", "archon",
]

func _ready() -> void:
	var fails := 0
	for id in IDS:
		var path := "res://scenes/levels/level_%s.tscn" % id
		if not ResourceLoader.exists(path):
			print("SKIP %s (no scene)" % id)
			continue
		var lvl: Node = (load(path) as PackedScene).instantiate()
		add_child(lvl)
		var pdmg := lvl.find_child("Damageable", true, false)
		if pdmg:
			pdmg.invulnerable = true
		await get_tree().create_timer(2.2).timeout  # build geometry + bake navmesh
		var def: Dictionary = LevelDefs.get_def(id)
		var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
		var exit: Vector3 = def.get("exit", Vector3.ZERO)
		if exit == Vector3.ZERO:
			print("SKIP %s (no authored exit — boss/objective level)" % id)
			lvl.queue_free()
			await get_tree().process_frame
			continue
		var map := get_world_3d().get_navigation_map()
		var p := NavigationServer3D.map_get_path(map, spawn, exit, true)
		var verdict := "NO-PATH"
		if p.size() >= 2:
			var endp := p[p.size() - 1]
			var gap := Vector2(endp.x - exit.x, endp.z - exit.z).length()
			verdict = "PASS gap=%.1f pts=%d" % [gap, p.size()] if gap < 5.0 else "FAIL gap=%.1f" % gap
		if verdict.begins_with("FAIL") or verdict == "NO-PATH":
			fails += 1
		print("NAV %s: %s  (spawn=%s exit=%s)" % [id, verdict, spawn, exit])
		lvl.queue_free()
		await get_tree().process_frame
	print("CAMPAIGN_NAV_SWEEP_DONE fails=%d" % fails)
	get_tree().quit()
