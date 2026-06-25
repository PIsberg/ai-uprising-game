class_name MatrixScreen
extends RefCounted
## Builds the assets the matrix-rain screen shader (shaders/matrix_rain.gdshader)
## needs — both generated procedurally and cached:
##   chars_tex(): a horizontal strip of 10 dot-matrix "glyphs" (the falling code).
##   noise_tex(): a 32x32 white-noise texture (column selection + distortion).
## material(color, energy) wires a ShaderMaterial for any 3D screen mesh.

const SHADER := preload("res://shaders/matrix_rain.gdshader")
const CELLS := 10
const CW := 20
const CH := 28

static var _chars: Texture2D = null
static var _noise: Texture2D = null

## 10 glyph cells, each a random 5x7 dot-matrix pattern — reads as digital code.
static func chars_tex() -> Texture2D:
	if _chars != null:
		return _chars
	var img := Image.create(CELLS * CW, CH, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	for c in CELLS:
		for gx in 5:
			for gy in 7:
				if _h(c * 97 + gx * 13 + gy * 7) < 0.45:
					continue
				var ox := c * CW + 1 + gx * 4
				var oy := 1 + gy * 4
				for dx in 3:
					for dy in 3:
						var x := ox + dx
						var y := oy + dy
						if x < CELLS * CW and y < CH:
							img.set_pixel(x, y, Color(1, 1, 1, 1))
	_chars = ImageTexture.create_from_image(img)
	return _chars

static func noise_tex() -> Texture2D:
	if _noise != null:
		return _noise
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var v := _h(x * 131 + y * 977)
			img.set_pixel(x, y, Color(v, v, v, 1))
	_noise = ImageTexture.create_from_image(img)
	return _noise

static func material(color: Color, energy: float = 3.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("chars", chars_tex())
	m.set_shader_parameter("noise_tex", noise_tex())
	m.set_shader_parameter("rain_color", Vector3(color.r, color.g, color.b))
	m.set_shader_parameter("emission_energy", energy)
	return m

static func _h(i: int) -> float:
	var s := sin(float(i) * 12.9898) * 43758.5453
	return s - floor(s)
