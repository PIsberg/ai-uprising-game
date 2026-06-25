class_name FlameMaterial
extends RefCounted
## Builds ShaderMaterials for the scrolling-noise flame shader
## (shaders/flame.gdshader): an eroding, panning noise plume that fades along its
## length and stays hot in the core. Reusable for any flame/energy VFX — rocket
## exhaust, jets, torches, muzzle gouts. The seamless noise texture is shared.

const SHADER := preload("res://shaders/flame.gdshader")
static var _noise_tex: Texture2D = null

## A shared seamless fbm noise texture for the erosion/scroll.
static func noise() -> Texture2D:
	if _noise_tex != null:
		return _noise_tex
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.035
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	_noise_tex = t
	return t

## Make a flame material. core = hot inner colour, edge = cooler rim colour.
static func make(core: Color, edge: Color, energy: float = 3.0,
		pan: Vector2 = Vector2(0.0, -8.0), density: float = 0.55,
		sharpness: float = 0.18) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("noise_texture", noise())
	m.set_shader_parameter("core_color", core)
	m.set_shader_parameter("edge_color", edge)
	m.set_shader_parameter("emission_energy", energy)
	m.set_shader_parameter("uv_pan", pan)
	m.set_shader_parameter("uv_scale", Vector2(1.0, 1.0))
	m.set_shader_parameter("noise_density", density)
	m.set_shader_parameter("cut_sharpness", sharpness)
	m.set_shader_parameter("noise_intensity", 1.0)
	return m
