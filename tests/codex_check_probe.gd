extends Node
const TARGETS := ["drone", "raptor", "gunner", "overseer"]
func _ready() -> void:
	for t in EnemyCodex.ORDER:
		GameState.discovered_enemies[t] = true
	_run.call_deferred()
func _run() -> void:
	var ps: PackedScene = load("res://scenes/ui/encyclopedia.tscn")
	var enc := ps.instantiate()
	get_tree().root.add_child(enc)
	await get_tree().create_timer(0.4).timeout
	for t in TARGETS:
		var idx: int = enc._types.find(t)
		if idx < 0:
			continue
		enc._index = idx
		enc._refresh()
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(OS.get_user_data_dir() + "/codexchk_%s.png" % t)
		print("SAVED ", t)
	get_tree().quit()
