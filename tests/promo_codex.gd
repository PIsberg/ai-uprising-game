extends Node
## Promo: enemy codex / bestiary entries → docs/screenshots/codex_*.png
const SHOTS := {17: "codex_ravager", 18: "codex_warmech", 23: "codex_titan"}

func _ready() -> void:
	for t in EnemyCodex.ORDER:
		GameState.discovered_enemies[t] = true
	_run.call_deferred()

func _run() -> void:
	var enc: Node = (load("res://scenes/ui/encyclopedia.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(enc)
	await get_tree().create_timer(0.8).timeout
	var idxs := SHOTS.keys()
	idxs.sort()
	for i in idxs:
		enc._index = i
		enc._refresh()
		await get_tree().create_timer(1.0).timeout   # let the model load + camera reframe
		await _save(SHOTS[i])
	enc.queue_free()
	get_tree().quit()

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var th := int(round(1600.0 * img.get_height() / float(img.get_width())))
	img.resize(1600, th, Image.INTERPOLATE_LANCZOS)
	img.save_png("res://docs/screenshots/%s.png" % name)
	print("SAVED ", name, " 1600x", th)
