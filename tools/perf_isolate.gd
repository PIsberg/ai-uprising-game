extends Node
## Isolates whether the ~195ms/frame "process" cost is rendering-submission
## (draw calls/materials) or pure script/game-logic by hiding ALL visible
## geometry in the loaded level and re-measuring the same way.
## Run: godot --path . --quit-after 3000 tools/perf_isolate.tscn

const LEVEL_ID := "gpt"

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DisplayServer.window_set_size(Vector2i(1280, 720))
	if GraphicsSettings:
		GraphicsSettings.quality = 2
		GraphicsSettings._apply_viewport()
	var lvl: Node = load("res://scenes/levels/level_%s.tscn" % LEVEL_ID).instantiate()
	add_child(lvl)
	for f in 90:
		await get_tree().process_frame

	await _measure("with full geometry visible")

	var all := lvl.find_children("*", "VisualInstance3D", true, false)
	var by_parent := {}
	for n in all:
		var cur: Node = n
		var second_level := "?"
		var chain := []
		while cur and cur != lvl:
			chain.append(cur.name)
			cur = cur.get_parent()
		chain.reverse()
		second_level = String(chain[0]) if chain.size() > 0 else "?"
		by_parent[second_level] = int(by_parent.get(second_level, 0)) + 1
	print("CENSUS total=%d" % all.size())
	var pkeys := by_parent.keys()
	pkeys.sort_custom(func(a, b): return by_parent[a] > by_parent[b])
	for k in pkeys:
		if by_parent[k] >= 5:
			print("CENSUS   %-30s %d" % [k, by_parent[k]])

	var hidden := 0
	for n in all:
		(n as VisualInstance3D).visible = false
		hidden += 1
	await _measure("all %d VisualInstance3D hidden" % hidden)

	# Also try: freeze all enemies (pause their scripts) to isolate AI/game logic.
	var enemies := get_tree().get_nodes_in_group("enemy")
	for e in enemies:
		(e as Node).set_process(false)
		(e as Node).set_physics_process(false)
	await _measure("with %d enemies' _process/_physics_process disabled" % enemies.size())

	print("PERF_ISOLATE_DONE")
	get_tree().quit()

func _measure(label: String) -> void:
	var t0 := Time.get_ticks_usec()
	var n := 100
	for f in n:
		await get_tree().process_frame
	var dt := (Time.get_ticks_usec() - t0) / 1000000.0
	var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	print("ISOLATE %-45s fps=%6.1f  process_ms=%6.2f" % [label, n / dt, proc_ms])
