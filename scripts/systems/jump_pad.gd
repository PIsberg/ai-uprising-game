class_name JumpPad
# @lat: [[level-system#Jump Pads]]
extends Area3D
## A launch pad: step on and it throws the player on a ballistic arc that lands
## on `to` (a world point on a deck). The arc tops out ARC m above the higher
## end, or at `max_apex` (feet height) when that is lower: indoors the builder
## passes the ceiling minus head room. The player owns no air control for the
## flight (Player.launch), so the arc lands where it was solved. Robots are not
## launched. Def key `jump_pads` (level_builder `_build_jump_pads`).
## tests/jump_pad_probe.

@export var to: Vector3 = Vector3.ZERO     ## world landing point (feet), on a deck
@export var max_apex: float = INF          ## world feet height the arc may not pass
@export var radius: float = 1.1

const ARC := 2.0         ## m the arc rises above the higher end
const REARM := 0.8       ## s before the pad launches the same player again
const PLAYER_LAYER := 2

var _cool := 0.0
var _ring_mat: StandardMaterial3D
var _t := 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = PLAYER_LAYER
	monitoring = true
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 0.8
	cs.shape = cyl
	cs.position = Vector3.UP * 0.4
	add_child(cs)
	_build_visual()
	body_entered.connect(_on_body)

## The feet height an arc from `from` to `to_at` tops out at.
static func apex_for(from: Vector3, to_at: Vector3, cap: float = INF) -> float:
	return minf(maxf(from.y, to_at.y) + ARC, cap)

## Launch velocity from `from` that lands on `to_at` over an apex at `apex`,
## under gravity `g`; [velocity, flight time].
static func solve(from: Vector3, to_at: Vector3, apex: float, g: float) -> Array:
	var up := maxf(apex - from.y, 0.05)
	var down := maxf(apex - to_at.y, 0.05)
	var vy := sqrt(2.0 * g * up)
	var t := vy / g + sqrt(2.0 * down / g)
	var flat := Vector3(to_at.x - from.x, 0.0, to_at.z - from.z)
	return [flat / t + Vector3.UP * vy, t]

func _on_body(b: Node) -> void:
	if _cool > 0.0 or not b.is_in_group("player") or not b.has_method("launch"):
		return
	var from: Vector3 = (b as Node3D).global_position
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var s := solve(from, to, apex_for(from, to, max_apex), g)
	b.launch(s[0], s[1])
	_cool = REARM
	_t = 1.0
	AudioBus.play_synth_at("grenade_throw", global_position, 0.0, 0.7)
	AudioBus.play_synth_at("charge", global_position, -6.0, 2.2)

func _build_visual() -> void:
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius + 0.1
	cm.height = 0.12
	base.mesh = cm
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.12, 0.13, 0.16)
	steel.metallic = 0.7
	steel.roughness = 0.4
	base.material_override = steel
	base.position = Vector3.UP * 0.06
	add_child(base)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.22
	tm.outer_radius = radius - 0.06
	ring.mesh = tm
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(0.2, 1.0, 0.85)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(0.2, 1.0, 0.85)
	_ring_mat.emission_energy_multiplier = 2.5
	ring.material_override = _ring_mat
	ring.scale = Vector3(1, 0.5, 1)
	ring.position = Vector3.UP * 0.13
	add_child(ring)
	# A chevron on the pad pointing where it throws you.
	var flat := Vector3(to.x - global_position.x, 0.0, to.z - global_position.z) if is_inside_tree() else Vector3.FORWARD
	var arrow := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.7, 0.5, 0.05)
	arrow.mesh = pm
	arrow.material_override = _ring_mat
	arrow.rotation = Vector3(-PI * 0.5, 0, 0)
	arrow.position = Vector3.UP * 0.14
	var holder := Node3D.new()
	add_child(holder)
	holder.add_child(arrow)
	if flat.length() > 0.1:
		holder.rotation.y = atan2(-flat.x, -flat.z)
	var light := OmniLight3D.new()
	light.light_color = Color(0.2, 1.0, 0.85)
	light.light_energy = 1.2
	light.omni_range = 3.5
	light.position = Vector3.UP * 0.6
	add_child(light)

func _physics_process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	_t = maxf(0.0, _t - delta * 2.5)
	_ring_mat.emission_energy_multiplier = 2.5 + 6.0 * _t + 0.8 * sin(Time.get_ticks_msec() / 250.0)
