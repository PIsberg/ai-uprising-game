class_name Blinker
extends MeshInstance3D
## Random on/off flicker for small prop status lights (server LEDs, terminal
## cursors). Duplicates its mesh's material so each instance blinks
## independently, and drives emission + albedo so it reads even unlit.

@export var min_on: float = 0.15
@export var max_on: float = 1.2
@export var min_off: float = 0.08
@export var max_off: float = 0.7
@export var on_energy: float = 3.0

var _mat: StandardMaterial3D
var _t: float = 0.0
var _next: float = 0.5
var _on: bool = true

func _ready() -> void:
	if mesh and mesh.material is StandardMaterial3D:
		_mat = mesh.material.duplicate()
		# Per-instance surface override; leaves the shared mesh resource alone.
		set_surface_override_material(0, _mat)
	_next = randf_range(min_on, max_on)

func _process(delta: float) -> void:
	if _mat == null:
		return
	_t += delta
	if _t < _next:
		return
	_t = 0.0
	_on = not _on
	_next = randf_range(min_on, max_on) if _on else randf_range(min_off, max_off)
	_mat.emission_energy_multiplier = on_energy if _on else 0.0
