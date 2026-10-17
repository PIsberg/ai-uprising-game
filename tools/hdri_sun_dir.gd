extends SceneTree
## Where the sun is in an HDRI panorama, for the lens flare (#234). A
## PanoramaSkyMaterial paints the sun into the photograph, so nothing in the
## scene says where it is; this measures it once so a level def can carry it
## as env `hdri_sun_dir` (docs/LEVEL_DEF_KEYS.md).
##
## Finds the brightest texel of the panorama after a box downsample to
## 512x256 (so the sun's disc wins over a single hot pixel) and turns its
## (u, v) into the direction Godot's sky shader samples it from:
##   u = atan2(x, -z) / TAU wrapped to [0, 1),   v = acos(y) / PI.
## Prints a Vector3 to paste into the def. tests/lens_flare_probe re-measures
## every def's value with sun_dir() and fails if they drift apart.
##   godot --headless --path . --script res://tools/hdri_sun_dir.gd -- res://assets/environments/hdri/<file>.hdr

const W := 512
const H := 256

func _init() -> void:
	var paths := OS.get_cmdline_user_args()
	if paths.is_empty():
		print("usage: --script res://tools/hdri_sun_dir.gd -- <panorama.hdr> [...]")
	for p in paths:
		var r := sun_dir(p)
		if r.is_empty():
			print("%s: could not load" % p)
			continue
		var d: Vector3 = r["dir"]
		print("%s: Vector3(%.3f, %.3f, %.3f)  elevation %.1f deg  peak %.1f x median" % [
			p, d.x, d.y, d.z, rad_to_deg(asin(clampf(d.y, -1.0, 1.0))), float(r["contrast"])])
	quit()

## {dir: Vector3, contrast: peak / median luminance}, or {} if unreadable.
static func sun_dir(path: String) -> Dictionary:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		return {}
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBF)
	img.resize(W, H, Image.INTERPOLATE_BILINEAR)
	var best := -1.0
	var bx := 0
	var by := 0
	var lums: Array[float] = []
	for y in H:
		for x in W:
			var c := img.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			lums.append(l)
			if l > best:
				best = l
				bx = x
				by = y
	lums.sort()
	var median := maxf(lums[lums.size() / 2], 1e-6)
	var theta := (bx + 0.5) / W * TAU
	var phi := (by + 0.5) / H * PI
	var dir := Vector3(sin(phi) * sin(theta), cos(phi), -sin(phi) * cos(theta))
	return {"dir": dir.normalized(), "contrast": best / median}
