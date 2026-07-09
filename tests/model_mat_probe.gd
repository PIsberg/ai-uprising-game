extends Node3D
## Import-cache corruption sweep. Godot's texture import can occasionally emit a
## garbage .ctex whose md5 still matches the source, so nothing re-imports it and
## the model renders with saturated magenta/cyan stripes (seen on the EyeDrone
## shell). Compares each imported texture against its own source PNG: block
## compression is lossy, so only a LARGE mean deviation means a corrupt cache.
##   godot --headless --path . res://tests/model_mat_probe.tscn

const DIRS := ["res://assets/models/robots/"]
const STEP := 16     ## sample stride
const BAD_MEAN := 0.10  ## mean |diff| per channel above this = corrupt, not lossy

func _ready() -> void:
	var bad: Array[String] = []
	var checked := 0
	for dir in DIRS:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".png"):
				continue
			var tex: Texture2D = load(dir + f)
			if tex == null:
				continue
			var got: Image = tex.get_image()
			if got == null:
				continue
			got.decompress()
			got.convert(Image.FORMAT_RGB8)
			var src := Image.new()
			if src.load(dir + f) != OK:
				continue
			src.convert(Image.FORMAT_RGB8)
			if src.get_size() != got.get_size():
				continue
			var acc := 0.0
			var n := 0
			for y in range(0, src.get_height(), STEP):
				for x in range(0, src.get_width(), STEP):
					var a := src.get_pixel(x, y)
					var b := got.get_pixel(x, y)
					# R/G only: normal maps import as BC5 (red-green), so their blue
					# channel legitimately differs from the source and would swamp
					# the signal. Real corruption shows up in R/G too.
					acc += absf(a.r - b.r) + absf(a.g - b.g)
					n += 2
			checked += 1
			var mean := acc / maxf(n, 1)
			if mean > BAD_MEAN:
				bad.append("%s mean=%.3f" % [f, mean])
	print("checked ", checked)
	if bad.is_empty():
		print("RESULT PASS  (no corrupt imports)")
	else:
		print("CORRUPT: ", bad)
		print("RESULT FAIL")
	get_tree().quit()
