extends Node3D

@export var lifetime: float = 0.06
var _age: float = 0.0
var _mat: StandardMaterial3D

@onready var mesh: MeshInstance3D = $MeshInstance3D

func setup(from: Vector3, to: Vector3, color: Color = Color(1.0, 0.85, 0.5)) -> void:
	global_position = from
	var dist := from.distance_to(to)
	if dist < 0.01:
		queue_free()
		return
	look_at(to, Vector3.UP)
	mesh.scale.z = dist
	mesh.position.z = -dist * 0.5
	# Per-shot glowing material in the weapon's tracer colour.
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = color
	_mat.emission_enabled = true
	_mat.emission = color
	_mat.emission_energy_multiplier = 7.0
	mesh.material_override = _mat
	# A short streak of light along the round so it lifts the environment.
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.2
	light.omni_range = 4.0
	light.position = Vector3(0, 0, -dist * 0.5)
	add_child(light)

func _process(delta: float) -> void:
	_age += delta
	if _age > lifetime:
		queue_free()
		return
	var a := 1.0 - (_age / lifetime)
	if _mat:
		_mat.albedo_color.a = a
		_mat.emission_energy_multiplier = 7.0 * a
