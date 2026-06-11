class_name ElectricBeam
extends Node3D
## Continuous lightning beam for BEAM-mode weapons. A faint straight core plus
## several jittered arc segments that re-randomize every frame, an impact glow
## light, and electric sparks at the hit point. The owning weapon calls
## `update_beam(from, to, hit)` every frame while firing and `deactivate()`
## when the trigger releases.

const SEGMENTS := 8

var color: Color = Color(0.45, 0.85, 1.0)

var _core: MeshInstance3D
var _core_mesh: CylinderMesh
var _arcs: Array[MeshInstance3D] = []
var _arc_mesh: BoxMesh
var _impact_light: OmniLight3D
var _muzzle_light: OmniLight3D
var _sparks: CPUParticles3D
var _mat: StandardMaterial3D
var _core_mat: StandardMaterial3D

func _ready() -> void:
	top_level = true # world-space: endpoints are global positions
	# Bright arc material shared by all jitter segments.
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	_mat.emission_enabled = true
	_mat.emission = color
	_mat.emission_energy_multiplier = 7.0
	# Softer, wider core the arcs dance around.
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_core_mat.albedo_color = Color(color.r, color.g, color.b, 0.28)
	_core_mat.emission_enabled = true
	_core_mat.emission = color
	_core_mat.emission_energy_multiplier = 3.0
	_core_mesh = CylinderMesh.new()
	_core_mesh.top_radius = 0.02
	_core_mesh.bottom_radius = 0.03
	_core_mesh.height = 1.0
	_core_mesh.radial_segments = 8
	_core_mesh.material = _core_mat
	_core = MeshInstance3D.new()
	_core.mesh = _core_mesh
	_core.visible = false
	add_child(_core)
	_arc_mesh = BoxMesh.new()
	_arc_mesh.size = Vector3(0.012, 0.012, 1.0)
	_arc_mesh.material = _mat
	for _i in SEGMENTS:
		var seg := MeshInstance3D.new()
		seg.mesh = _arc_mesh
		seg.visible = false
		add_child(seg)
		_arcs.append(seg)
	_impact_light = OmniLight3D.new()
	_impact_light.light_color = color
	_impact_light.light_energy = 0.0
	_impact_light.omni_range = 4.0
	add_child(_impact_light)
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = color
	_muzzle_light.light_energy = 0.0
	_muzzle_light.omni_range = 2.5
	add_child(_muzzle_light)
	_sparks = CPUParticles3D.new()
	_sparks.emitting = false
	_sparks.amount = 14
	_sparks.lifetime = 0.3
	_sparks.spread = 70.0
	_sparks.gravity = Vector3(0, -14, 0)
	_sparks.initial_velocity_min = 2.0
	_sparks.initial_velocity_max = 6.0
	_sparks.scale_amount_min = 0.3
	_sparks.scale_amount_max = 0.7
	var sm := BoxMesh.new()
	sm.size = Vector3(0.02, 0.02, 0.02)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.emission_enabled = true
	smat.albedo_color = color
	smat.emission = color
	smat.emission_energy_multiplier = 5.0
	sm.material = smat
	_sparks.mesh = sm
	add_child(_sparks)

func update_beam(from: Vector3, to: Vector3, hit_something: bool) -> void:
	var dir := to - from
	var dist := dir.length()
	if dist < 0.1:
		deactivate()
		return
	dir /= dist
	_stretch_between(_core, from, to)
	_core.visible = true
	# Jittered arcs: a polyline of SEGMENTS links whose interior points wander
	# off-axis each frame — re-randomizing every frame is what reads as electricity.
	var prev := from
	for i in _arcs.size():
		var t := float(i + 1) / float(_arcs.size())
		var p := from + dir * (dist * t)
		if i < _arcs.size() - 1:
			# Sag envelope: zero jitter at the muzzle and the hit, widest mid-beam.
			var amp := 0.18 * sin(PI * t) * minf(dist * 0.2, 1.0)
			p += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 2.0 * amp
		_stretch_between(_arcs[i], prev, p)
		_arcs[i].visible = true
		prev = p
	# Lights flicker slightly so nearby surfaces dance.
	_muzzle_light.global_position = from
	_muzzle_light.light_energy = randf_range(1.2, 2.0)
	_impact_light.global_position = to - dir * 0.1
	_impact_light.light_energy = randf_range(2.5, 4.5) if hit_something else 0.0
	_sparks.global_position = to
	_sparks.direction = -dir
	_sparks.emitting = hit_something

func deactivate() -> void:
	_core.visible = false
	for seg in _arcs:
		seg.visible = false
	_impact_light.light_energy = 0.0
	_muzzle_light.light_energy = 0.0
	_sparks.emitting = false

## Position + aim a unit-length mesh so it spans exactly from a to b.
func _stretch_between(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		mi.visible = false
		return
	var dn := d / l
	var up := Vector3.UP if absf(dn.y) < 0.99 else Vector3.RIGHT
	var basis := Basis.looking_at(dn, up)
	# Cylinder height runs along Y, box length along Z — orient each accordingly.
	if mi == _core:
		basis = basis * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1, l, 1))
	else:
		basis = basis * Basis.from_scale(Vector3(1, 1, l))
	mi.global_transform = Transform3D(basis, (a + b) * 0.5)

## Tint everything (called once by the weapon from its tracer_color).
func set_color(c: Color) -> void:
	color = c
	if _mat:
		_mat.albedo_color = Color(c.r, c.g, c.b, 0.9)
		_mat.emission = c
		_core_mat.albedo_color = Color(c.r, c.g, c.b, 0.28)
		_core_mat.emission = c
		_impact_light.light_color = c
		_muzzle_light.light_color = c
