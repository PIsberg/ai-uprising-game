class_name FirewallNode
extends StaticBody3D
## The relay pylon that powers a FirewallBarrier. Shoot it and the wall it feeds
## drops. Sits on the world layer (1) so hitscan and splash hit it like any
## prop, and throws a faint light column skyward so the player can find it from
## the far side of the wall it powers.

signal destroyed

@export var max_health: float = 70.0
@export var accent: Color = Color(1.0, 0.18, 0.12)

const EXPLOSION := preload("res://scenes/fx/grenade_explosion.tscn")

var hp: Damageable
var _dead: bool = false
var _t: float = 0.0
var _orb_mat: StandardMaterial3D
var _ring_a: MeshInstance3D
var _ring_b: MeshInstance3D
var _light: OmniLight3D

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("firewall_node")
	_build_visual()
	hp = Damageable.new()
	hp.name = "Damageable"
	hp.max_health = max_health
	add_child(hp)
	hp.died.connect(_on_died)
	hp.damaged.connect(_on_damaged)

func _metal() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.11, 0.13)
	m.metallic = 0.8
	m.roughness = 0.35
	return m

func _glow(energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = accent
	m.emission_enabled = true
	m.emission = accent
	m.emission_energy_multiplier = energy
	return m

func _build_visual() -> void:
	# Tapered plinth with a glowing collar: reads as a machine, not a crate.
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 0.6
	cm.height = 1.1
	cm.radial_segments = 6
	base.mesh = cm
	base.material_override = _metal()
	base.position.y = 0.55
	add_child(base)

	var collar := MeshInstance3D.new()
	var col := CylinderMesh.new()
	col.top_radius = 0.38
	col.bottom_radius = 0.38
	col.height = 0.08
	col.radial_segments = 6
	collar.mesh = col
	collar.material_override = _glow(3.0)
	collar.position.y = 1.08
	add_child(collar)

	# The relay: a faceted orb in two counter-rotating rings.
	var orb := MeshInstance3D.new()
	var om := SphereMesh.new()
	om.radius = 0.32
	om.height = 0.64
	om.radial_segments = 8
	om.rings = 4
	orb.mesh = om
	_orb_mat = _glow(4.0)
	orb.material_override = _orb_mat
	orb.position.y = 1.55
	add_child(orb)

	var ring_mat := _metal()
	ring_mat.emission_enabled = true
	ring_mat.emission = accent
	ring_mat.emission_energy_multiplier = 0.8
	for i in 2:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.44
		tm.outer_radius = 0.52
		tm.rings = 20
		tm.ring_segments = 6
		ring.mesh = tm
		ring.material_override = ring_mat
		ring.position.y = 1.55
		ring.rotation_degrees = Vector3(90, 0, 0) if i == 0 else Vector3(0, 0, 90)
		add_child(ring)
		if i == 0: _ring_a = ring
		else: _ring_b = ring

	# Locator column: an additive shaft straight up, visible over cover.
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.05
	bm.bottom_radius = 0.16
	bm.height = 14.0
	bm.radial_segments = 8
	bm.cap_top = false
	bm.cap_bottom = false
	beam.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bmat.albedo_color = Color(accent.r, accent.g, accent.b, 0.35)
	beam.material_override = bmat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = 1.55 + 7.0
	add_child(beam)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.1, 2.0, 1.1)
	cs.shape = bs
	cs.position.y = 1.0
	add_child(cs)

	_light = OmniLight3D.new()
	_light.light_color = accent
	_light.light_energy = 2.0
	_light.omni_range = 6.0
	_light.position.y = 1.6
	add_child(_light)

func _process(delta: float) -> void:
	_t += delta
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	if _orb_mat:
		_orb_mat.emission_energy_multiplier = 3.0 + pulse * 2.5
	if _light:
		_light.light_energy = 1.6 + pulse * 1.0
	if _ring_a:
		_ring_a.rotate_object_local(Vector3.UP, delta * 2.2)
	if _ring_b:
		_ring_b.rotate_object_local(Vector3.UP, -delta * 3.1)

func _on_damaged(_amount: float, _source) -> void:
	if _orb_mat:
		_orb_mat.emission_energy_multiplier = 9.0

func _on_died(_source) -> void:
	if _dead:
		return
	_dead = true
	destroyed.emit()
	if not is_inside_tree():
		return
	var fx := EXPLOSION.instantiate()
	get_parent().add_child(fx)
	(fx as Node3D).global_position = global_position + Vector3.UP * 1.5
	AudioBus.play_synth_at("explosion", global_position, 0.0, 0.8)
	queue_free()