class_name BossPortal
extends Node3D
## A dimensional gate a boss arrives through: a swirling energy disc (portal
## shader) ringed by a bright emissive torus, with a coloured light. open()
## grows it from nothing; close() collapses it and frees the node. Face it at
## the player with face() before opening.

const PORTAL_SHADER := preload("res://shaders/portal.gdshader")

@export var radius: float = 4.5
@export var color: Color = Color(0.45, 0.8, 1.0)

var _root: Node3D
var _mat: ShaderMaterial
var _ring: MeshInstance3D
var _light: OmniLight3D
var _t: float = 0.0

func _ready() -> void:
	# Everything hangs off a scalable root so open/close is one tween on scale.
	_root = Node3D.new()
	_root.scale = Vector3.ZERO
	add_child(_root)

	var disc := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(radius * 2.0, radius * 2.0)
	_mat = ShaderMaterial.new()
	_mat.shader = PORTAL_SHADER
	_mat.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	_mat.set_shader_parameter("rim_color", Vector3(
		minf(color.r + 0.45, 1.0), minf(color.g + 0.3, 1.0), minf(color.b + 0.15, 1.0)))
	_mat.set_shader_parameter("intensity", 1.0)
	qm.material = _mat
	disc.mesh = qm
	_root.add_child(disc)

	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.92
	tm.outer_radius = radius * 1.05
	tm.rings = 32
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rmat.albedo_color = color
	rmat.emission_enabled = true
	rmat.emission = color
	rmat.emission_energy_multiplier = 6.0
	tm.material = rmat
	_ring.mesh = tm
	# TorusMesh sits in the XZ plane (axis +Y); stand it up to share the quad's
	# XY plane so the ring frames the energy disc head-on.
	_ring.rotation_degrees = Vector3(90, 0, 0)
	_root.add_child(_ring)

	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 8.0
	_light.omni_range = radius * 3.0
	_light.shadow_enabled = false
	_root.add_child(_light)

## Orient the gate to face a world point (flattened so it never tips fully flat).
func face(point: Vector3) -> void:
	var t := Vector3(point.x, global_position.y, point.z)
	if t.distance_to(global_position) > 0.05:
		look_at(t, Vector3.UP)

func open(dur: float = 0.55) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_root, "scale", Vector3.ONE, dur)

func close(dur: float = 0.5) -> void:
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(_root, "scale", Vector3.ZERO, dur)
	tw.parallel().tween_method(
		func(v: float): _mat.set_shader_parameter("intensity", v), 1.0, 0.0, dur)
	tw.tween_callback(queue_free)

func _process(delta: float) -> void:
	_t += delta
	if _ring:
		_ring.rotate_z(delta * 0.8)
	if _light:
		_light.light_energy = 7.0 + 2.0 * sin(_t * 6.0)
