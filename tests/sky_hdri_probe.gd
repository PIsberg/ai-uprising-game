extends Node
## Every photographic sky a level def uses ships VRAM-compressed and still HDR.
## The two Poly Haven skies imported lossless (RGBE9995): 8 MB each in every
## release pack, four times what BC6H takes at the same 2048x1024 (#56).
## Compression must not flatten them, though: the sun in the suburb sky peaks
## at 624, and a sky clamped to 1.0 loses the bright key that its IBL and
## reflections come from. So beside the size budget, the imported sky's peak
## and mean brightness are compared with the source .hdr decoded directly.
##   godot --headless --path . --audio-driver Dummy res://tests/sky_hdri_probe.tscn

const MAX_BYTES := 2_300_000      # BC6H: 1 byte per texel, 2048x1024 = 2 MiB
const MIN_PEAK_RATIO := 0.5       # imported peak / source peak
const MEAN_TOLERANCE := 0.1       # |imported mean - source mean| / source mean

var _ok := true

func _ready() -> void:
	_run.call_deferred()

func _skies() -> Dictionary:
	var out := {}
	for id: String in LevelDefs._defs().keys():
		var env: Dictionary = LevelDefs.get_def(id).get("env", {})
		if env.has("hdri"):
			out[env["hdri"]] = id
	return out

func _stats(img: Image) -> Vector2:
	# x = brightest channel anywhere (sampled), y = mean of the channel maxima.
	var peak := 0.0
	var total := 0.0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			var m: float = max(c.r, max(c.g, c.b))
			peak = max(peak, m)
			total += m
			n += 1
	return Vector2(peak, total / max(n, 1))

func _bad(msg: String) -> void:
	_ok = false
	print("BAD  " + msg)

func _run() -> void:
	var skies := _skies()
	if skies.size() < 2:
		_bad("expected the 2 HDRI skies (suburb, suburb_boss), found %d" % skies.size())
	for path: String in skies:
		var tex: Texture2D = load(path)
		if tex == null:
			_bad("%s (%s): does not load" % [path, skies[path]])
			continue
		var img := tex.get_image()
		var bytes := img.get_data_size()
		print("%s (%s): %dx%d format %d compressed=%s %d bytes" % [path.get_file(), skies[path],
			img.get_width(), img.get_height(), img.get_format(), img.is_compressed(), bytes])
		if bytes > MAX_BYTES:
			_bad("%s: %d bytes in the pack, budget %d (VRAM-compress it)" % [path.get_file(), bytes, MAX_BYTES])
		var src := Image.load_from_file(path)
		if src == null or src.is_empty():
			_bad("%s: source .hdr does not decode for the reference" % path.get_file())
			continue
		if img.is_compressed():
			img.decompress()
		var got := _stats(img)
		var want := _stats(src)
		print("  peak %.2f (source %.2f)  mean %.4f (source %.4f)" % [got.x, want.x, got.y, want.y])
		if got.x < want.x * MIN_PEAK_RATIO:
			_bad("%s: peak %.2f is under %.0f%% of the source's %.2f (HDR range lost)" % [
				path.get_file(), got.x, MIN_PEAK_RATIO * 100.0, want.x])
		if absf(got.y - want.y) > want.y * MEAN_TOLERANCE:
			_bad("%s: mean %.4f vs source %.4f, off by more than %.0f%%" % [
				path.get_file(), got.y, want.y, MEAN_TOLERANCE * 100.0])
	print("RESULT %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)
