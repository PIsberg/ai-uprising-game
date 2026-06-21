extends Node
## Dev probe: captures the comic intro's three panels and a few Encyclopedia
## entries to user://codex_*.png, then quits. Seeds a handful of discovered
## enemies so the codex has content. Run windowed:
##   godot --path . res://tests/codex_probe.tscn

const SHOTS := ["drone", "mech", "archon"] # entries to grab in the codex

func _ready() -> void:
	# Seed discovery directly (bypass save) so the codex shows entries.
	for t in ["drone", "android", "spider", "mech", "skitter", "gunner", "archon", "titan"]:
		GameState.discovered_enemies[t] = true
	_run.call_deferred() # wait until the tree is done setting up before add_child

func _run() -> void:
	await _capture_comic()
	await _capture_codex()
	get_tree().quit()

func _capture_comic() -> void:
	var ps: PackedScene = load("res://scenes/cutscene/comic_intro.tscn")
	var comic := ps.instantiate()
	# Don't let it actually load level 1 at the end of the probe.
	get_tree().root.add_child(comic)
	for i in 3:
		# Drive each panel: wait for the flash+reveal to settle, grab it.
		await _wait(1.0 if i == 0 else 2.6)
		await _save("codex_comic_panel%d" % (i + 1))
	comic.queue_free()
	await _wait(0.2)

func _capture_codex() -> void:
	var ps: PackedScene = load("res://scenes/ui/encyclopedia.tscn")
	var enc := ps.instantiate()
	get_tree().root.add_child(enc)
	await _wait(0.6)
	await _save("codex_entry_0")
	# Advance a couple of entries.
	enc._on_next()
	await _wait(0.6)
	await _save("codex_entry_1")
	enc._on_next()
	enc._on_next()
	await _wait(0.6)
	await _save("codex_entry_2")
	enc.queue_free()

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OS.get_user_data_dir() + "/%s.png" % name
	img.save_png(path)
	print("SAVED ", path)
