class_name ElectricBeam
extends Node3D
## Continuous lightning beam for BEAM-mode weapons. A faint straight core plus
## several jittered arc segments that re-randomize every frame, an impact glow
## light, and electric sparks at the hit point. The owning weapon calls
## `update_beam(from, to, hit)` every frame while firing and `deactivate()`
## when the trigger releases.

const SEGMENTS := 12       # denser polyline → more jagged, more electric
const NUM_FORKS := 4       # branch tendrils that split off the bolt
const FORK_SEGS := 3       # links per fork

var color: Color = Color(0.45, 0.85, 1.0)

var _core: MeshInstance3D
var _core_mesh: CylinderMesh
var _arcs: Array[MeshInstance3D] = []
var _arc_mesh: BoxMesh
var _forks: Array[MeshInstance3D] = []
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _impact_light: OmniLight3D
var _muzzle_light: OmniLight3D
var _sparks: CPUParticles3D
var _mat: StandardMaterial3D
var _core_mat: StandardMaterial3D

# Extra "more juice" layers: a blinding white-hot inner filament down the whole
# beam, billboard flares blooming at the muzzle and the hit point, and a slow
# scorch the beam sears into whatever it lingers on.
var _hot_core: MeshInstance3D
var _hot_mat: StandardMaterial3D
var _impact_flare: MeshInstance3D
var _impact_flare_mat: StandardMaterial3D
var _muzzle_flare: MeshInstance3D
var _muzzle_flare_mat: StandardMaterial3D
var _scorch_cooldown: float = 0.0
var _time: float = 0.0

static var _flare_tex: Texture2D = null

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
	# Glow geometry must never render into shadow maps — it's light, not matter.
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)
	# Wide, faint outer halo so the whole bolt blooms with a thick atmospheric glow.
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.albedo_color = Color(color.r, color.g, color.b, 0.12)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = color
	_glow_mat.emission_energy_multiplier = 1.6
	var glow_mesh := CylinderMesh.new()
	glow_mesh.top_radius = 0.09
	glow_mesh.bottom_radius = 0.11
	glow_mesh.height = 1.0
	glow_mesh.radial_segments = 10
	glow_mesh.material = _glow_mat
	_glow = MeshInstance3D.new()
	_glow.mesh = glow_mesh
	_glow.visible = false
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)
	# White-hot inner filament: a razor-thin near-white core that overdrives the
	# colour so the centre of the beam reads as searing energy, not just a glow.
	_hot_mat = StandardMaterial3D.new()
	_hot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hot_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_hot_mat.albedo_color = Color(1, 1, 1, 0.95)
	_hot_mat.emission_enabled = true
	_hot_mat.emission = _hot_tint()
	_hot_mat.emission_energy_multiplier = 12.0
	var hot_mesh := CylinderMesh.new()
	hot_mesh.top_radius = 0.008
	hot_mesh.bottom_radius = 0.012
	hot_mesh.height = 1.0
	hot_mesh.radial_segments = 6
	hot_mesh.material = _hot_mat
	_hot_core = MeshInstance3D.new()
	_hot_core.mesh = hot_mesh
	_hot_core.visible = false
	_hot_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hot_core)
	_arc_mesh = BoxMesh.new()
	_arc_mesh.size = Vector3(0.012, 0.012, 1.0)
	_arc_mesh.material = _mat
	for _i in SEGMENTS:
		var seg := MeshInstance3D.new()
		seg.mesh = _arc_mesh
		seg.visible = false
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(seg)
		_arcs.append(seg)
	# Branch tendrils that split off the bolt and flicker in/out each frame — the
	# detail that sells a high-voltage arc rather than a tidy laser line.
	for _f in NUM_FORKS * FORK_SEGS:
		var fk := MeshInstance3D.new()
		fk.mesh = _arc_mesh
		fk.visible = false
		fk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fk)
		_forks.append(fk)
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
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sparks)
	# Camera-facing glow flares — a bloom kicking off the emitter and a fierce
	# burning-point flare where the beam bites into a surface.
	_muzzle_flare = _make_flare(0.5)
	_muzzle_flare_mat = _muzzle_flare.get_surface_override_material(0)
	add_child(_muzzle_flare)
	_impact_flare = _make_flare(0.9)
	_impact_flare_mat = _impact_flare.get_surface_override_material(0)
	add_child(_impact_flare)

## A billboarded additive quad with a soft radial glow texture, used for the
## muzzle and impact blooms. `size` is its world width in metres.
func _make_flare(size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _flare_texture()
	m.albedo_color = Color(color.r, color.g, color.b, 1.0)
	m.emission_enabled = true
	m.emission_texture = _flare_texture()
	m.emission = color
	m.emission_energy_multiplier = 6.0
	mi.set_surface_override_material(0, m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi

## A soft radial glow (bright opaque centre fading to transparent edge), built
## once and shared by every beam's flares.
static func _flare_texture() -> Texture2D:
	if _flare_tex != null:
		return _flare_tex
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s * 0.5, s * 0.5)
	for y in s:
		for x in s:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(c) / (s * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 2.2)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_flare_tex = ImageTexture.create_from_image(img)
	return _flare_tex

## A whiter, hotter version of the beam colour for the inner filament.
func _hot_tint() -> Color:
	return color.lerp(Color(1, 1, 1), 0.6)

func update_beam(from: Vector3, to: Vector3, hit_something: bool) -> void:
	var dir := to - from
	var dist := dir.length()
	if dist < 0.1:
		deactivate()
		return
	dir /= dist
	_time += get_process_delta_time()
	# Energy throb so the beam pulses rather than sitting at a flat brightness.
	var throb := 1.0 + 0.25 * sin(_time * 38.0)
	_stretch_between(_core, from, to)
	_core.visible = true
	_core_mat.emission_energy_multiplier = 3.0 * throb
	# Fat outer halo runs the whole bolt and breathes with the throb.
	_stretch_between(_glow, from, to)
	_glow.visible = true
	_glow_mat.emission_energy_multiplier = 1.6 * throb
	# White-hot inner filament runs the full beam, slightly proud of the core.
	_stretch_between(_hot_core, from, to)
	_hot_core.visible = true
	_hot_mat.emission_energy_multiplier = 12.0 * throb
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
	# Branch forks: short jagged tendrils anchored along the bolt, splaying off in
	# a random perpendicular direction and blinking each frame so the arc crackles.
	var fi := 0
	for k in NUM_FORKS:
		var at := 0.18 + 0.64 * (float(k) + randf() * 0.6) / float(NUM_FORKS)
		var anchor := from + dir * (dist * at)
		var perp := dir.cross(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5)).normalized()
		var blen := randf_range(0.15, 0.5) * minf(dist * 0.25, 1.0)
		var fp := anchor
		var lit := randf() < 0.7 # the whole fork blinks in or out together
		for s in FORK_SEGS:
			var np := fp + perp * (blen / FORK_SEGS) + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.12
			_stretch_between(_forks[fi], fp, np)
			_forks[fi].visible = lit
			fp = np
			fi += 1
	# Lights flicker slightly so nearby surfaces dance.
	_muzzle_light.global_position = from
	_muzzle_light.light_energy = randf_range(1.2, 2.0)
	_impact_light.global_position = to - dir * 0.1
	_impact_light.light_energy = randf_range(2.5, 4.5) if hit_something else 0.0
	_sparks.global_position = to
	_sparks.direction = -dir
	_sparks.emitting = hit_something
	# Muzzle bloom always; impact flare only where the beam lands, throbbing and
	# pulled just off the surface so it doesn't z-fight.
	_muzzle_flare.global_position = from
	_muzzle_flare.visible = true
	_muzzle_flare.scale = Vector3.ONE * (0.85 + 0.3 * sin(_time * 50.0))
	_impact_flare.visible = hit_something
	if hit_something:
		_impact_flare.global_position = to - dir * 0.05
		_impact_flare.scale = Vector3.ONE * (0.8 + 0.35 * sin(_time * 44.0) + randf() * 0.2)
		# Sear a lingering scorch into the struck surface a few times a second.
		_scorch_cooldown -= get_process_delta_time()
		if _scorch_cooldown <= 0.0:
			_scorch_cooldown = 0.12
			_burn_scorch(to, dir)

## Drop a small, short-lived scorch mark where the beam is burning. Throttled by
## the caller so a held beam leaves a trail of char rather than one per frame.
func _burn_scorch(at: Vector3, dir: Vector3) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var sc := ScorchMark.new()
	sc.radius = randf_range(0.22, 0.4)
	sc.hold = 1.4
	sc.fade = 1.2
	tree.current_scene.add_child(sc)
	sc.global_position = at - dir * 0.02

func deactivate() -> void:
	_core.visible = false
	_hot_core.visible = false
	if _glow:
		_glow.visible = false
	for seg in _arcs:
		seg.visible = false
	for fk in _forks:
		fk.visible = false
	_impact_light.light_energy = 0.0
	_muzzle_light.light_energy = 0.0
	_sparks.emitting = false
	if _muzzle_flare:
		_muzzle_flare.visible = false
	if _impact_flare:
		_impact_flare.visible = false

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
	if mi.mesh is CylinderMesh:
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
	if _glow_mat:
		_glow_mat.albedo_color = Color(c.r, c.g, c.b, 0.12)
		_glow_mat.emission = c
	if _hot_mat:
		_hot_mat.emission = _hot_tint()
	if _muzzle_flare_mat:
		_muzzle_flare_mat.albedo_color = Color(c.r, c.g, c.b, 1.0)
		_muzzle_flare_mat.emission = c
	if _impact_flare_mat:
		_impact_flare_mat.albedo_color = Color(c.r, c.g, c.b, 1.0)
		_impact_flare_mat.emission = c
