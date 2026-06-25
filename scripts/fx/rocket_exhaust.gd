class_name RocketExhaust
extends Node3D
## A downward retro-thruster plume for the GOLIATH-IX sky-drop: a flickering
## additive flame cone, a hot white inner core, a warm ground light and a GPU
## spark spray, all firing straight down. `intensity` 1.0 = full burn; call
## shut_down() and it ramps the burn to nothing and frees itself.

@export var color: Color = Color(1.0, 0.5, 0.16)
@export var flame_length: float = 4.2
@export var flame_radius: float = 0.7

var intensity: float = 1.0

var _t: float = 0.0
var _flame_mat: ShaderMaterial    ## scrolling-noise flame (shaders/flame.gdshader)
var _core_mat: StandardMaterial3D
var _flame: MeshInstance3D
var _core: MeshInstance3D
var _light: OmniLight3D
var _particles: GPUParticles3D

const FLAME_ENERGY := 5.0

func _ready() -> void:
	# Outer plume: the eroding scrolling-noise flame, hot-white core into the
	# thruster colour at the edges, panning fast downward so it reads as fire.
	_flame = _make_cone(flame_radius, flame_length, color, 7.0)
	var fm := FlameMaterial.make(Color(1.0, 0.82, 0.4), color, FLAME_ENERGY, Vector2(0.0, -9.0), 0.5, 0.24)
	_flame.mesh.material = fm
	_flame_mat = fm
	add_child(_flame)
	_core = _make_cone(flame_radius * 0.4, flame_length * 0.62, Color(1.0, 0.97, 0.88), 7.0)
	_core_mat = _core.mesh.material
	add_child(_core)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 9.0
	_light.omni_range = 10.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, -flame_length * 0.5, 0)
	add_child(_light)
	_add_sparks()

# A tapered cylinder: the narrow nozzle sits at y=0 (the foot), flaring downward.
func _make_cone(radius: float, length: float, c: Color, energy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 14
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(c.r, c.g, c.b, 0.85)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	cm.material = m
	mi.mesh = cm
	mi.position = Vector3(0, -length * 0.5, 0)
	return mi

func _add_sparks() -> void:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.5
	p.local_coords = false
	p.explosiveness = 0.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 16.0
	pm.initial_velocity_min = 12.0
	pm.initial_velocity_max = 24.0
	pm.gravity = Vector3(0, -3.0, 0)
	pm.scale_min = 0.05
	pm.scale_max = 0.2
	pm.color = Color(1.0, 0.72, 0.3)
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.22, 0.22)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.albedo_color = Color(1.0, 0.75, 0.35)
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.7, 0.3)
	sm.emission_energy_multiplier = 6.0
	qm.material = sm
	p.draw_pass_1 = qm
	add_child(p)
	_particles = p

func _process(delta: float) -> void:
	_t += delta
	var flick := 0.82 + 0.18 * sin(_t * 45.0) + 0.08 * sin(_t * 17.0)
	var k := flick * intensity
	if _flame_mat:
		_flame_mat.set_shader_parameter("emission_energy", FLAME_ENERGY * k)
	if _core_mat:
		_core_mat.emission_energy_multiplier = 7.0 * k
	if _light:
		_light.light_energy = 9.0 * k
	if _flame:
		_flame.scale = Vector3(intensity, 1.0 + 0.08 * sin(_t * 30.0), intensity)
	if _core:
		_core.scale = Vector3(intensity, 1.0, intensity)

## Ramp the burn out over `dur` seconds, then remove the node.
func shut_down(dur: float = 0.4) -> void:
	if _particles:
		_particles.emitting = false
	var tw := create_tween()
	tw.tween_method(func(v: float): intensity = v, intensity, 0.0, dur)
	tw.tween_callback(queue_free)
