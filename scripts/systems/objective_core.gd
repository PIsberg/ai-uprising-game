class_name ObjectiveCore
extends StaticBody3D
# @lat: [[level-system#Jam-Shielded Relays]]
## A shootable objective device (reactor / mainframe core). Has its own
## Damageable; when destroyed it completes its level task and erupts in a big
## explosion. Built entirely in code, glowing so it's easy to spot. Sits on
## collision layer 1 so hitscan + explosive splash already hit it.

@export var task_id: String = "core"
@export var max_health: float = 220.0
@export var core_color: Color = Color(1.0, 0.35, 0.2)
## Mesh-shielded (hivemind's relays): a shield bubble makes the core immune
## until a jam zone (jam_zone.gd) covers it, the same rule as a hive unit's
## shield. A JamZone only detects the enemy layer and the core sits on the
## world layer, so the core measures its own distance to live zones instead.
## Only author it on a level that hands the player the jammer ("jammer" def),
## or the core cannot be destroyed: tests/jam_relay_probe enforces that.
@export var jam_shielded: bool = false

const EXPLOSION := preload("res://scenes/fx/grenade_explosion.tscn")

var hp: Damageable
var _dead: bool = false
var _t: float = 0.0
var _core_mat: StandardMaterial3D
var _light: OmniLight3D
var _ring_a: MeshInstance3D
var _ring_b: MeshInstance3D
var _shield: MeshInstance3D
var _shield_mat: StandardMaterial3D
var _shield_flare: float = 0.0
## True while a jam zone covers the core (always true when not jam_shielded).
var exposed: bool = true

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("objective")
	add_to_group("objective_core")
	_build_visual()
	hp = Damageable.new()
	hp.name = "Damageable"
	hp.max_health = max_health
	add_child(hp)
	hp.died.connect(_on_destroyed)
	if jam_shielded:
		_build_shield()
		_update_shield(0.0)

## The mesh shield: an additive bubble over the orb, cyan like a hive unit's.
func _build_shield() -> void:
	_shield = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.5
	sm.height = 3.0
	_shield_mat = StandardMaterial3D.new()
	_shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shield_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_shield_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shield_mat.albedo_color = Color(0.3, 0.7, 1.0, 0.16)
	_shield_mat.emission_enabled = true
	_shield_mat.emission = Color(0.35, 0.75, 1.0)
	_shield_mat.emission_energy_multiplier = 0.5
	sm.material = _shield_mat
	_shield.mesh = sm
	_shield.position = Vector3(0, 1.3, 0)
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shield)

func _in_jam() -> bool:
	var c := global_position + Vector3(0, 1.3, 0)
	for z in get_tree().get_nodes_in_group("jam_zone"):
		if is_instance_valid(z) and (z as Node3D).global_position.distance_to(c) <= float(z.get("radius")) + 0.5:
			return true
	return false

func _update_shield(delta: float) -> void:
	exposed = _in_jam()
	hp.invulnerable = not exposed
	_shield_flare = maxf(0.0, _shield_flare - delta * 3.0)
	if _shield:
		_shield.visible = not exposed
		_shield_mat.albedo_color.a = 0.16 + 0.3 * _shield_flare
		_shield_mat.emission_energy_multiplier = 0.5 + 2.5 * _shield_flare

## Damageable calls this when a hit lands on the closed shield.
func notify_shield_hit(_source = null) -> void:
	_shield_flare = 1.0
	GameState.teach_once("jam_relay", "The relay is mesh-shielded. Plant a jam beacon on it, then shoot.")

func _build_visual() -> void:
	# Housing — a dark armoured plinth (short, so the core orb sits exposed on top).
	var housing := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(1.5, 1.1, 1.5)
	housing.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.12, 0.13, 0.16)
	hmat.metallic = 0.7
	hmat.roughness = 0.4
	housing.material_override = hmat
	housing.position = Vector3(0, 0.55, 0)
	add_child(housing)

	# A glowing emissive ring collar where the orb meets the plinth.
	var collar := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.62
	tm.outer_radius = 0.8
	collar.mesh = tm
	var ringmat := StandardMaterial3D.new()
	ringmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ringmat.emission_enabled = true
	ringmat.albedo_color = core_color
	ringmat.emission = core_color
	ringmat.emission_energy_multiplier = 3.0
	collar.material_override = ringmat
	collar.position = Vector3(0, 1.12, 0)
	add_child(collar)

	# Exposed glowing core orb, riding above the plinth.
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.6
	sm.height = 1.2
	core.mesh = sm
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.albedo_color = core_color
	_core_mat.emission_enabled = true
	_core_mat.emission = core_color
	_core_mat.emission_energy_multiplier = 4.0
	core.material_override = _core_mat
	core.position = Vector3(0, 1.75, 0)
	add_child(core)

	# Two counter-rotating containment rings caging the orb — it reads as a
	# volatile reactor you must crack open, not just a glowing ball.
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.7, 0.72, 0.78)
	ring_mat.metallic = 0.9
	ring_mat.roughness = 0.25
	ring_mat.emission_enabled = true
	ring_mat.emission = core_color
	ring_mat.emission_energy_multiplier = 0.6
	for i in 2:
		var ring := MeshInstance3D.new()
		var rtm := TorusMesh.new()
		rtm.inner_radius = 0.82
		rtm.outer_radius = 0.92
		rtm.rings = 24
		rtm.ring_segments = 8
		ring.mesh = rtm
		ring.material_override = ring_mat
		ring.position = Vector3(0, 1.75, 0)
		ring.rotation_degrees = Vector3(90, 0, 0) if i == 0 else Vector3(0, 0, 90)
		add_child(ring)
		if i == 0: _ring_a = ring
		else: _ring_b = ring

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.6, 2.6, 1.6)
	cs.shape = bs
	cs.position = Vector3(0, 1.3, 0)
	add_child(cs)

	_light = OmniLight3D.new()
	_light.light_color = core_color
	_light.light_energy = 3.0
	_light.omni_range = 8.0
	_light.position = Vector3(0, 1.75, 0)
	add_child(_light)

func _process(delta: float) -> void:
	_t += delta
	if jam_shielded and not _dead:
		_update_shield(delta)
	if _core_mat:
		_core_mat.emission_energy_multiplier = 4.0 + sin(_t * 4.0) * 1.5
	if _light:
		_light.light_energy = 3.0 + sin(_t * 4.0) * 1.0
	if _ring_a:
		_ring_a.rotate_object_local(Vector3.UP, delta * 1.4)
	if _ring_b:
		_ring_b.rotate_object_local(Vector3.UP, -delta * 1.9)

func _on_destroyed(_source: Node) -> void:
	if _dead:
		return
	_dead = true
	GameState.complete_task(task_id)
	var fx := EXPLOSION.instantiate()
	get_parent().add_child(fx)
	(fx as Node3D).global_position = global_position + Vector3.UP * 1.2
	(fx as Node3D).scale = Vector3.ONE * 1.8
	if has_node("/root/AudioBus"):
		var ab: Node = get_node("/root/AudioBus")
		if ab.has_method("play_synth_at"):
			ab.play_synth_at("explosion", global_position, 4.0, 0.55)
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(0.8)
	queue_free()
