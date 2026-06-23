class_name HoloBillboard
extends Node3D
## A floating holographic propaganda sign: a dark projector base throws a
## glowing, flickering panel of AI doctrine into the air, with a slogan in
## holographic text over it. Pure set-dressing (no collision). The text glitches,
## the panel bobs, and the whole thing occasionally drops out like bad signal.

@export var text: String = "OBEY"
@export var color: Color = Color(0.4, 0.85, 1.0)
@export var panel_size: Vector2 = Vector2(3.4, 1.7)
@export var height: float = 2.6        ## Panel centre height above the base.

const HOLO_SHADER := preload("res://shaders/hologram.gdshader")

var _panel_root: Node3D
var _label: Label3D
var _mat: ShaderMaterial
var _light: AreaLight3D
var _t: float = 0.0
var _glitch_cd: float = 0.0
var _base_alpha: float = 0.55

func _ready() -> void:
	_t = randf() * 10.0
	_glitch_cd = randf_range(2.0, 6.0)
	_build_base()
	_build_panel()

func _build_base() -> void:
	# Dark machined projector puck with a glowing emitter ring + two prongs.
	var puck := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.45; cm.bottom_radius = 0.6; cm.height = 0.3; cm.radial_segments = 16
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.09, 0.11)
	dark.metallic = 0.7; dark.roughness = 0.4
	cm.material = dark
	puck.mesh = cm
	puck.position = Vector3(0, 0.15, 0)
	add_child(puck)

	var emat := StandardMaterial3D.new()
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emat.albedo_color = color
	emat.emission_enabled = true
	emat.emission = color
	emat.emission_energy_multiplier = 4.0
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.34; tm.outer_radius = 0.46; tm.rings = 20; tm.ring_segments = 8
	tm.material = emat
	ring.mesh = tm
	ring.position = Vector3(0, 0.32, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

func _build_panel() -> void:
	_panel_root = Node3D.new()
	_panel_root.position = Vector3(0, height, 0)
	add_child(_panel_root)

	# The glowing holo panel.
	var panel := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = panel_size
	_mat = ShaderMaterial.new()
	_mat.shader = HOLO_SHADER
	_mat.set_shader_parameter("holo_color", Vector3(color.r, color.g, color.b))
	_mat.set_shader_parameter("alpha", _base_alpha)
	_mat.set_shader_parameter("scan_count", 70.0 + randf() * 40.0)
	qm.material = _mat
	panel.mesh = qm
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_panel_root.add_child(panel)

	# Holographic frame.
	var emat := StandardMaterial3D.new()
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	emat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	emat.albedo_color = color
	emat.emission_enabled = true
	emat.emission = color
	emat.emission_energy_multiplier = 3.0
	for edge in [
		{"size": Vector3(panel_size.x + 0.1, 0.04, 0.04), "y": panel_size.y * 0.5},
		{"size": Vector3(panel_size.x + 0.1, 0.04, 0.04), "y": -panel_size.y * 0.5},
	]:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = edge["size"]; bm.material = emat
		bar.mesh = bm
		bar.position = Vector3(0, edge["y"], 0)
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_panel_root.add_child(bar)

	# The slogan, in holographic text floating just in front of the panel.
	_label = Label3D.new()
	_label.text = text
	_label.font_size = 96
	_label.outline_size = 28
	_label.modulate = color
	_label.outline_modulate = Color(0.02, 0.05, 0.08, 0.9)
	_label.double_sided = true
	_label.width = panel_size.x * 200.0
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.pixel_size = 0.0042
	_label.position = Vector3(0, 0, 0.02)
	_panel_root.add_child(_label)

	# Glow cast by the projection — a rect AreaLight3D (4.7) shaped to the panel
	# so the light reads as spilling FROM the sign, not from a point behind it.
	# Emits along -Z, so face it forward (+Z, toward whoever's reading it).
	_light = AreaLight3D.new()
	_light.light_color = color
	_light.light_energy = 2.0
	_light.area_size = panel_size * 0.85
	_light.area_normalize_energy = false
	_light.area_range = panel_size.x * 2.5
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0, 0.1)
	_light.rotation_degrees = Vector3(0, 180, 0)
	_panel_root.add_child(_light)

func _process(delta: float) -> void:
	_t += delta
	# Gentle bob + a constant slow yaw so the sign turns lazily for any sightline.
	if _panel_root:
		_panel_root.position.y = height + sin(_t * 1.1) * 0.08
	rotation.y += delta * 0.25
	# Flicker the text + light together; punctuated by brief glitch dropouts.
	_glitch_cd -= delta
	var glitching := _glitch_cd < 0.0 and _glitch_cd > -0.12
	if _glitch_cd < -0.12:
		_glitch_cd = randf_range(2.5, 7.0)
	var base := 0.0 if glitching else (0.78 + 0.22 * sin(_t * 11.0) + (randf() - 0.5) * 0.1)
	if _label:
		_label.modulate.a = clampf(base, 0.0, 1.0)
		_label.position.x = (randf() - 0.5) * 0.06 if glitching else 0.0
	if _light:
		_light.light_energy = (0.2 if glitching else 1.6 + sin(_t * 9.0) * 0.5)
	if _mat:
		_mat.set_shader_parameter("alpha", 0.08 if glitching else _base_alpha)
