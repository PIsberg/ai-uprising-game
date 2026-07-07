class_name JamZone
extends Area3D
## An ephemeral, hyper-local GEOFENCED SIGNAL-JAMMING field, projected by a beacon
## the player shoots into a wall or floor (see jammer_controller.gd). Any hive unit
## inside the boundary loses its link to the AI: enter_jam()/exit_jam() on the enemy
## drop its shield and leave it disoriented. The zone fades out after `lifetime` —
## you get a handful of seconds of window per beacon, so WHERE and WHEN you place it
## is the whole puzzle.

@export var radius := 5.0
@export var lifetime := 7.0
@export var color := Color(0.35, 0.8, 1.0)

const ENEMY_LAYER := 4

var _t := 0.0
var _inside: Array = []           ## enemies currently jammed by THIS zone
var _dome: MeshInstance3D
var _dome_mat: StandardMaterial3D
var _light: OmniLight3D
var _clock := 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = ENEMY_LAYER
	monitoring = true
	add_to_group("jam_zone")
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = radius
	cs.shape = sp
	add_child(cs)
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)
	_build_visual()
	# Anything already standing inside when the beacon lands is jammed immediately.
	for b in get_overlapping_bodies():
		_on_enter(b)

func _build_visual() -> void:
	_dome = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	_dome_mat = StandardMaterial3D.new()
	_dome_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dome_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_dome_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dome_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_dome_mat.albedo_color = Color(color.r, color.g, color.b, 0.12)
	_dome_mat.emission_enabled = true
	_dome_mat.emission = color
	_dome_mat.emission_energy_multiplier = 0.5
	sm.material = _dome_mat
	_dome.mesh = sm
	_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dome)
	# A bright floor ring so the boundary reads on the ground where you fight.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.2
	tm.outer_radius = radius
	tm.rings = 40
	tm.ring_segments = 6
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.emission_enabled = true
	rmat.emission = color
	rmat.albedo_color = color
	rmat.emission_energy_multiplier = 2.4
	tm.material = rmat
	ring.mesh = tm
	ring.position = Vector3(0, -radius + 0.15, 0) # sit on the floor under the anchor
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 2.4
	_light.omni_range = radius * 2.0
	_light.shadow_enabled = false
	add_child(_light)

func _on_enter(b: Node) -> void:
	if b.has_method("enter_jam"):
		if not _inside.has(b):
			_inside.append(b)
			b.enter_jam()

func _on_exit(b: Node) -> void:
	if _inside.has(b):
		_inside.erase(b)
		if b.has_method("exit_jam"):
			b.exit_jam()

func _process(delta: float) -> void:
	_t += delta
	_clock += delta
	if _light:
		_light.light_energy = 2.0 + sin(_clock * 5.0) * 0.5
	# Fade out over the last second, then release everyone and free.
	var fade := clampf((lifetime - _t) / 1.0, 0.0, 1.0)
	if _dome_mat:
		_dome_mat.albedo_color.a = 0.12 * fade + 0.02
	if _t >= lifetime:
		_release_all()
		queue_free()

func _release_all() -> void:
	for b in _inside:
		if is_instance_valid(b) and b.has_method("exit_jam"):
			b.exit_jam()
	_inside.clear()

func _exit_tree() -> void:
	_release_all()
