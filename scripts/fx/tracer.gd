extends Node3D
## Shot visual with two modes:
##  - default: an instant full-length streak that fades in ~60ms (player fire —
##    snappy, never obscures your own view)
##  - bolt: a long glowing segment that TRAVELS from the muzzle to the impact
##    point (enemy fire — you can see the laser coming and read where it came
##    from). Damage stays hitscan; the bolt is theatre.

@export var lifetime: float = 0.06
@export var bolt: bool = false
@export var bolt_speed: float = 55.0   ## m/s of the visual bolt
@export var bolt_length: float = 3.5   ## glowing segment length (m)
@export var bolt_width: float = 2.6    ## thickness multiplier vs the base mesh
@export var color_override: Color = Color(0, 0, 0, 0) ## Used when alpha > 0.

var _age: float = 0.0
var _mat: StandardMaterial3D
var _dist: float = 0.0
var _seg: float = 0.0
var _traveled: float = 0.0
var _light: OmniLight3D

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
	# Per-shot glowing material in the weapon's tracer colour.
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = color
	_mat.emission_enabled = true
	_mat.emission = color
	_mat.emission_energy_multiplier = 10.0 # HDR-hot bolt — blooms hard, sears on HDR
	mesh.material_override = _mat
	_light = OmniLight3D.new()
	_light.light_color = color
	add_child(_light)
	if bolt:
		_seg = minf(bolt_length, _dist)
		mesh.scale = Vector3(bolt_width, bolt_width, _seg)
		mesh.position.z = -_seg * 0.5 # tail at the muzzle, nose downrange
		_light.light_energy = 3.0
		_light.omni_range = 5.0
		_light.position = mesh.position
	else:
		mesh.scale.z = _dist
		mesh.position.z = -_dist * 0.5
		# A short streak of light along the round so it lifts the environment.
		_light.light_energy = 2.2
		_light.omni_range = 4.0
		_light.position = Vector3(0, 0, -_dist * 0.5)

func _process(delta: float) -> void:
	if bolt:
		# Slide the segment down the firing line; free once it has fully
		# passed the impact point (the impact FX marks the hit itself).
		_traveled += bolt_speed * delta
		var z := -_traveled - _seg * 0.5
		mesh.position.z = z
		_light.position.z = z
		# Free once the tail clears the impact point (impact FX marks the hit).
		if _traveled >= _dist or _traveled > 400.0:
			queue_free()
		return
	_age += delta
	if _age > lifetime:
		queue_free()
		return
	var a := 1.0 - (_age / lifetime)
	if _mat:
		_mat.albedo_color.a = a
		_mat.emission_energy_multiplier = 10.0 * a
