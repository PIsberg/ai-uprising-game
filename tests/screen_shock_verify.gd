extends Node
## Proves the blast screen-warp actually displaces the image, rather than the
## uniforms binding but doing nothing. Compares the clean capture against the
## mid-expansion one from screen_shock_shot and bins the per-pixel difference by
## aspect-corrected radius from the blast's screen centre.
##
## Animated film grain means ANY two frames differ everywhere, so a flat diff
## profile proves nothing. A real refraction ring shows up as one radial band
## far above the rest — that peak is what this asserts.
##
##   godot --headless --path . --audio-driver Dummy res://tests/screen_shock_verify.tscn

const BINS := 24
const CENTRE := Vector2(0.5, 0.5) # where screen_shock_shot places the blast
## The shot holds progress at screen_shock_shot.PROGRESS, so the crest sits at
## PROGRESS * 0.78 in aspect-corrected units — bin ~10 of 24 over a 0..0.65 sweep.
const EXPECT_CREST := 0.35 * 0.78

func _ready() -> void:
	var dir := OS.get_user_data_dir()
	var a := Image.new()
	var b := Image.new()
	if a.load(dir + "/shock_off.png") != OK or b.load(dir + "/shock_mid.png") != OK:
		print("  FAIL could not load captures — run tests/screen_shock_shot.tscn (windowed) first")
		print("RESULT FAIL")
		get_tree().quit()
		return
	if a.get_size() != b.get_size():
		print("  FAIL capture sizes differ")
		print("RESULT FAIL")
		get_tree().quit()
		return

	var w := a.get_width()
	var h := a.get_height()
	var aspect := float(w) / float(h)
	var sums := PackedFloat64Array()
	var counts := PackedInt32Array()
	sums.resize(BINS)
	counts.resize(BINS)
	var max_r := 0.65

	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var uv := Vector2(float(x) / float(w), float(y) / float(h))
			var d := (uv - CENTRE) * Vector2(aspect, 1.0)
			var r := d.length()
			if r < max_r:
				var bin := int((r / max_r) * float(BINS))
				bin = clampi(bin, 0, BINS - 1)
				var ca := a.get_pixel(x, y)
				var cb := b.get_pixel(x, y)
				var diff: float = absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
				sums[bin] += diff
				counts[bin] += 1
			x += 3
		y += 3

	var means: Array[float] = []
	for i in BINS:
		means.append(float(sums[i]) / maxf(float(counts[i]), 1.0))

	# Peak bin vs the median bin: grain is uniform, a ring is not.
	var sorted := means.duplicate()
	sorted.sort()
	var median: float = sorted[BINS / 2]
	var peak := 0.0
	var peak_bin := 0
	for i in BINS:
		if means[i] > peak:
			peak = means[i]
			peak_bin = i

	print("radial diff profile (bin: mean |Δrgb|)")
	for i in BINS:
		var r_mid := (float(i) + 0.5) / float(BINS) * max_r
		var bar := "#".repeat(int(means[i] / maxf(peak, 0.0001) * 40.0))
		print("  %5.3f  %.4f  %s" % [r_mid, means[i], bar])

	var expect_bin := int((EXPECT_CREST / max_r) * float(BINS))
	var ratio := peak / maxf(median, 0.0001)
	var fails: Array[String] = []

	if ratio > 2.5:
		print("  ok   peak bin is %.1fx the median — a structured ring, not grain" % ratio)
	else:
		print("  FAIL diff profile is flat (peak/median %.2f) — warp is not displacing pixels" % ratio)
		fails.append("flat profile")

	if absi(peak_bin - expect_bin) <= 3:
		print("  ok   crest lands at bin %d, expected ~%d" % [peak_bin, expect_bin])
	else:
		print("  FAIL crest at bin %d, expected ~%d — ring is the wrong radius" % [peak_bin, expect_bin])
		fails.append("crest radius")

	print("RESULT %s" % ("PASS" if fails.is_empty() else "FAIL"))
	get_tree().quit()
