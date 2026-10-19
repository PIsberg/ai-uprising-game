extends Node3D
## Shot visual with two modes:
##  - default: an instant full-length streak that fades in ~60ms (player fire —
##    snappy, never obscures your own view)
##  - bolt: a long glowing segment that TRAVELS from the muzzle to the impact
##    point (enemy fire — you can see the laser coming and read where it came
##    from). Damage stays hitscan; the bolt is theatre.
## Either way it is drawn as a soft streak (shaders/tracer_streak.gdshader): a
## flat card along the line of fire that turns about that line to face the
## camera every frame, with a white-hot core, a halo in the shot colour, a bright
## nose and a fading tail. The scene's cylinder only sets the streak's width.
## Its spill light is taken from the FX light budget (FXLights). Covered by
## tests/tracer_streak_probe.

const SHADER: Shader = preload("res://shaders/tracer_streak.gdshader")
## The card is this many times the scene cylinder's diameter: the halo needs room
## either side of a core about as wide as the old rod.
const CARD_SPREAD := 4.0

@export var lifetime: float = 0.06
@export var bolt: bool = false
@export var bolt_speed: float = 55.0   ## m/s of the visual bolt
@export var bolt_length: float = 3.5   ## glowing segment length (m)
@export var bolt_width: float = 2.6    ## thickness multiplier vs the base mesh
@export var color_override: Color = Color(0, 0, 0, 0) ## Used when alpha > 0.

var _age: float = 0.0
var _mat: ShaderMaterial
var _dist: float = 0.0
var _seg: float = 0.0
var _traveled: float = 0.0
var _light: OmniLight3D = null
var _width: float = 0.0
var _card_scale := Vector3.ONE

@onready var mesh: MeshInstance3D = $MeshInstance3D

func setup(from: Vector3, to: Vector3, color: Color = Color(1.0, 0.85, 0.5)) -> void:
	if color_override.a > 0.0:
		color = color_override
	global_position = from
	_dist = from.distance_to(to)
	if _dist < 0.01:
		queue_free()
		return
	look_at(to, Vector3.UP)
	# The scene's rod is only a size: swap it for a unit card along local z.
	var rod := mesh.mesh as CylinderMesh
	_width = (rod.top_radius * 2.0 if rod else 0.024) * CARD_SPREAD
	var card := PlaneMesh.new()
	card.size = Vector2.ONE
	mesh.mesh = card
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("tint", color)
	mesh.material_override = _mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if FXLights.take():
		_light = OmniLight3D.new()
		_light.light_color = color
		_light.tree_exited.connect(FXLights.give)
		add_child(_light)
	if bolt:
		_seg = minf(bolt_length, _dist)
		_place(-_seg * 0.5, _width * bolt_width, _seg)
		if _light:
			_light.light_energy = 3.0
			_light.omni_range = 5.0
	else:
		_place(-_dist * 0.5, _width, _dist)
		# A short streak of light along the round so it lifts the environment.
		if _light:
			_light.light_energy = 2.2
			_light.omni_range = 4.0
	_face_camera()

## Put the card's centre `z` down the line, `w` wide and `l` long.
func _place(z: float, w: float, l: float) -> void:
	_card_scale = Vector3(w, 1.0, l)
	mesh.transform = Transform3D(Basis().scaled(_card_scale), Vector3(0, 0, z))
	if _light:
		_light.position = Vector3(0, 0, z)

## Roll the card about the line of fire so its face (local +Y) points at the camera.
func _face_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := to_local(cam.global_position) - mesh.position
	var roll := atan2(-c.x, c.y)
	mesh.basis = Basis(Vector3.BACK, roll) * Basis().scaled(_card_scale)

func _process(delta: float) -> void:
	if bolt:
		# Slide the segment down the firing line; free once it has fully
		# passed the impact point (the impact FX marks the hit itself).
		_traveled += bolt_speed * delta
		var z := -_traveled - _seg * 0.5
		mesh.position.z = z
		if _light:
			_light.position.z = z
		# Free once the tail clears the impact point (impact FX marks the hit).
		if _traveled >= _dist or _traveled > 400.0:
			queue_free()
			return
		_face_camera()
		return
	_age += delta
	if _age > lifetime:
		queue_free()
		return
	var a := 1.0 - (_age / lifetime)
	if _mat:
		_mat.set_shader_parameter("fade", a)
	_face_camera()
