extends Node
## Windowed: the colourblind overlay corrects the FINISHED frame on screen.
## colorblind_probe checks the wiring headless; only a real render shows whether
## the overlay's screen read sees the pixels under it. Two swatches:
##   * left, a plain red panel on the Armory's layer (60), the menu case;
##   * right, a green panel under a layer-0 screen-reading pass, the level case
##     (the player's post-process samples the screen before the overlay does).
## With Deuteranopia each pixel must equal colorblind_matrix(2) * the swatch
## colour, within TOL; with Off it must be the swatch colour unchanged.
##   godot --path . res://tests/colorblind_render_probe.tscn

const TOL := 0.03
const RED := Color(0.85, 0.15, 0.1)
const GREEN := Color(0.25, 0.65, 0.1)
const PASSTHROUGH := "shader_type canvas_item;\nuniform sampler2D s : hint_screen_texture, filter_nearest;\nvoid fragment() { COLOR = vec4(texture(s, SCREEN_UV).rgb, 1.0); }\n"

var _fail: Array[String] = []

func _check(cond: bool, label: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

func _panel(layer: int, color: Color, left: bool) -> CanvasLayer:
	var cl := CanvasLayer.new()
	cl.layer = layer
	var r := ColorRect.new()
	r.color = color
	r.anchor_left = 0.0 if left else 0.5
	r.anchor_right = 0.5 if left else 1.0
	r.anchor_bottom = 1.0
	cl.add_child(r)
	add_child(cl)
	return cl

func _sample(frac_x: float) -> Color:
	var img := get_viewport().get_texture().get_image()
	return img.get_pixel(int(img.get_width() * frac_x), img.get_height() / 2)

static func _expect(m: Basis, c: Color) -> Color:
	var v := m * Vector3(c.r, c.g, c.b)
	return Color(maxf(v.x, 0.0), maxf(v.y, 0.0), maxf(v.z, 0.0))

static func _dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

func _frames(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw

func _run() -> void:
	var gs := GraphicsSettings
	var original: int = int(gs.colorblind_mode)
	_panel(60, RED, true)
	_panel(-1, GREEN, false)
	var post := CanvasLayer.new()
	post.layer = 0
	var pr := ColorRect.new()
	pr.anchor_left = 0.5
	pr.anchor_right = 1.0
	pr.anchor_bottom = 1.0
	var sh := Shader.new()
	sh.code = PASSTHROUGH
	var pm := ShaderMaterial.new()
	pm.shader = sh
	pr.material = pm
	post.add_child(pr)
	add_child(post)

	gs.colorblind_mode = 0
	gs.call("_apply_colorblind")
	await _frames(4)
	var off_l := _sample(0.25)
	var off_r := _sample(0.75)
	_check(_dist(off_l, RED) < TOL, "Off: menu swatch unchanged (%s)" % off_l)
	_check(_dist(off_r, GREEN) < TOL, "Off: level swatch unchanged (%s)" % off_r)

	gs.colorblind_mode = 2
	gs.call("_apply_colorblind")
	await _frames(4)
	var m: Basis = gs.colorblind_matrix(2)
	var on_l := _sample(0.25)
	var on_r := _sample(0.75)
	_check(_dist(on_l, _expect(m, RED)) < TOL, "Deuteranopia: menu swatch %s, expected %s" % [on_l, _expect(m, RED)])
	_check(_dist(on_r, _expect(m, GREEN)) < TOL, "Deuteranopia: level swatch under a screen read %s, expected %s" % [on_r, _expect(m, GREEN)])

	gs.colorblind_mode = original
	gs.call("_apply_colorblind")
	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit(0 if _fail.is_empty() else 1)
