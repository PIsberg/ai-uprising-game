extends Node
## Measures how abruptly a fluid bed's edge meets the floor, from the isolated
## top-down captures written by tests/fluid_shot.
##
## The complaint this answers is "it looks like something on top of the floor,
## not integrated with it". That is a step discontinuity at the rim: floor
## pixel, then fluid pixel, with nothing between. So the metric is the STEEPEST
## adjacent-pixel luminance jump in a window around where the rim is known to
## fall — a hard cut spikes, a dissolved shoreline stays flat.
##
## (A 10%-90% transition width was tried first and is wrong for lava: it assumes
## two flat plateaus, and the molten flow veins swing brighter than the shore
## does, so it measures turbulence instead of the edge. Peak gradient at a known
## location is robust to whatever the fluid's interior is doing.)
##
## Run fluid_shot twice (stash the change for the "before" pass), then:
##   godot --headless --path . --audio-driver Dummy res://tests/fluid_edge_verify.tscn

## Must match tests/fluid_shot.
const BED_HALF := 5.0
const CAM_Y := 14.0
const FOV := 75.0
## Pixels either side of the computed rim to search for the steepest step.
const WINDOW_PX := 70
## Above this, adjacent pixels are stepping rather than ramping.
const HARD_EDGE := 0.10

var _fail: Array[String] = []

func _ready() -> void:
	var dir := OS.get_user_data_dir()
	for kind in ["water", "lava"]:
		var after := _rim_gradient(dir + "/fluid_%s.png" % kind)
		var before := _rim_gradient(dir + "/fluid_%s_before.png" % kind)
		if after < 0.0:
			print("  FAIL %s: no capture — run tests/fluid_shot.tscn (windowed) first" % kind)
			_fail.append(kind + " missing")
			continue
		if before < 0.0:
			print("%s: after %.4f (no before capture to compare)" % [kind, after])
		else:
			print("%s peak rim step: before %.4f -> after %.4f" % [kind, before, after])

		if after < HARD_EDGE:
			print("  ok   %s rim ramps (peak step %.4f < %.2f) — blended into the floor"
				% [kind, after, HARD_EDGE])
		else:
			print("  FAIL %s rim still steps (peak %.4f)" % [kind, after])
			_fail.append(kind + " hard edge")
		if before >= 0.0:
			if after < before:
				print("  ok   %s softened by %.0f%%" % [kind, (1.0 - after / maxf(before, 1e-6)) * 100.0])
			else:
				print("  FAIL %s did not soften" % kind)
				_fail.append(kind + " not softened")

	print("RESULT %s" % ("PASS" if _fail.is_empty() else "FAIL"))
	get_tree().quit()

## Steepest adjacent-pixel luminance step near the rim. -1.0 if no capture.
func _rim_gradient(path: String) -> float:
	var img := Image.new()
	if img.load(path) != OK:
		return -1.0
	var w := img.get_width()
	var h := img.get_height()
	# Camera looks straight down with a vertical FOV, so metres map to pixels
	# identically on both axes.
	var px_per_m := float(h) / (2.0 * CAM_Y * tan(deg_to_rad(FOV * 0.5)))
	var rim_x := int(float(w) * 0.5 + BED_HALF * px_per_m)
	var lo := maxi(rim_x - WINDOW_PX, 1)
	var hi := mini(rim_x + WINDOW_PX, w - 1)
	if hi <= lo:
		return -1.0

	# Average a few rows so a single noisy scanline cannot dominate.
	var peak := 0.0
	for dy in [-24, 0, 24]:
		var y := clampi(h / 2 + dy, 1, h - 2)
		for x in range(lo, hi):
			var a := img.get_pixel(x, y)
			var b := img.get_pixel(x + 1, y)
			var la := 0.299 * a.r + 0.587 * a.g + 0.114 * a.b
			var lb := 0.299 * b.r + 0.587 * b.g + 0.114 * b.b
			peak = maxf(peak, absf(lb - la))
	return peak
