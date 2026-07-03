extends Node
## Contact sheets of EVERY codex entry: browses the Encyclopedia through all
## of EnemyCodex.ORDER, thumbnails each entry and composites grids to
## user://codex_sheet_N.png — for eyeballing stray FX / misoriented models.
##   godot --path . res://tests/codex_sheet_probe.tscn

const COLS := 4
const ROWS := 3
const TH_W := 480
const TH_H := 300

func _ready() -> void:
	for t in EnemyCodex.ORDER:
		GameState.discovered_enemies[t] = true
	_run.call_deferred()

func _run() -> void:
	var ps: PackedScene = load("res://scenes/ui/encyclopedia.tscn")
	var enc := ps.instantiate()
	get_tree().root.add_child(enc)
	await get_tree().create_timer(0.5).timeout
	var font := ThemeDB.fallback_font
	var per_sheet := COLS * ROWS
	var sheet: Image = null
	var sheet_idx := 0
	var cell := 0
	for i in enc._types.size():
		enc._index = i
		enc._refresh()
		await get_tree().create_timer(0.45).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(TH_W, TH_H, Image.INTERPOLATE_BILINEAR)
		if sheet == null:
			sheet = Image.create(TH_W * COLS, TH_H * ROWS, false, Image.FORMAT_RGBA8)
		var cx := (cell % COLS) * TH_W
		var cy := (cell / COLS) * TH_H
		sheet.blit_rect(img, Rect2i(0, 0, TH_W, TH_H), Vector2i(cx, cy))
		cell += 1
		if cell == per_sheet or i == enc._types.size() - 1:
			sheet.save_png(OS.get_user_data_dir() + "/codex_sheet_%d.png" % sheet_idx)
			print("SAVED sheet ", sheet_idx, " ending at ", enc._types[i])
			sheet_idx += 1
			cell = 0
			sheet = null
	print("RESULT PASS")
	get_tree().quit()
