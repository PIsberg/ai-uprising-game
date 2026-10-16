class_name LowGravField
# @lat: [[level-system#Low-Gravity Fields]]
extends Node3D
## A column of alien low gravity: within `radius` of this node (its origin on
## the floor) and up to `height` above it, the player's and every grounded
## robot's gravity is multiplied by `scale`, so a normal jump carries you up
## onto ledges you could not otherwise reach, and robots that leave the floor
## in it (knocked, pouncing, stepping off) drift slowly, easy to shoot. Leave
## the column and full gravity is back at once. Launches (jump pads, bumpers)
## keep their solved arcs (Player/EnemyBase ignore the scale while launched).
## Flyers have their own gravity-free movement and are unaffected.
## The column is drawn as a violet shimmer with rising motes and a floor ring,
## and walking up teaches the rule once. Def key `low_grav` (level_builder
## `_build_low_grav`). tests/low_grav_probe.

const DEFAULT_SCALE := 0.3
const TEACH_REACH := 10.0
const TEACH_TEXT := "LOW GRAVITY: inside the violet column you jump much higher and fall slowly. So does anything else in it."
const COLOR := Color(0.62, 0.42, 1.0)

@export var radius: float = 4.0
@export var height: float = 10.0
@export var gravity: float = DEFAULT_SCALE

## Bodies whose gravity_scale this field set, so it only restores its own.
var _held: Dictionary = {}
var _shell_mat: StandardMaterial3D
var _t := 0.0

func _ready() -> void:
	add_to_group("low_grav_field")
	_build()

func _build() -> void:
	_shell_mat = StandardMaterial3D.new()
	_shell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shell_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_shell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shell_mat.albedo_color = Color(COLOR, 0.08)
	var shell := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 32
	cm.cap_top = false
	cm.cap_bottom = false
	shell.mesh = cm
	shell.material_override = _shell_mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.position = Vector3.UP * height * 0.5
	add_child(shell)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = COLOR
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.15
	tm.outer_radius = radius
	ring.mesh = tm
	ring.material_override = ring_mat
	ring.position = Vector3.UP * 0.05
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	# Rising motes: the column reads as "things float here" before you test it.
	var motes := CPUParticles3D.new()
	motes.amount = int(clampf(radius * radius * 3.0, 24.0, 120.0))
	motes.lifetime = 4.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(radius * 0.7, 0.2, radius * 0.7)
	motes.direction = Vector3.UP
	motes.spread = 8.0
	motes.gravity = Vector3.ZERO
	motes.initial_velocity_min = height / 6.0
	motes.initial_velocity_max = height / 4.0
	var mm := SphereMesh.new()
	mm.radius = 0.05
	mm.height = 0.1
	mm.radial_segments = 6
	mm.rings = 3
	var mmat := StandardMaterial3D.new()
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.albedo_color = COLOR.lightened(0.4)
	mm.material = mmat
	motes.mesh = mm
	motes.position = Vector3.UP * 0.2
	add_child(motes)

## Feet of `n` inside the column.
func contains(n: Node3D) -> bool:
	var l := n.global_position - global_position
	return Vector2(l.x, l.z).length() <= radius and l.y >= -0.5 and l.y <= height

func _physics_process(delta: float) -> void:
	_t += delta
	_shell_mat.albedo_color = Color(COLOR, 0.07 + 0.03 * sin(_t * 2.0))
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p and p.global_position.distance_to(global_position) <= radius + TEACH_REACH:
		GameState.teach_once("low_grav", TEACH_TEXT)
	var bodies: Array = get_tree().get_nodes_in_group("enemy")
	if p:
		bodies.append(p)
	for b in bodies:
		if not is_instance_valid(b) or not ("gravity_scale" in b):
			continue
		var inside := contains(b)
		if inside and not _held.has(b):
			_held[b] = true
			b.gravity_scale = gravity
		elif not inside and _held.has(b):
			_held.erase(b)
			b.gravity_scale = 1.0
	for b in _held.keys():
		if not is_instance_valid(b):
			_held.erase(b)
