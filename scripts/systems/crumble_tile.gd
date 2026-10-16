class_name CrumbleTile
# @lat: [[level-system#Crumbling Slabs]]
extends StaticBody3D
## A slab of cooled slag over a hazard bed, one stepping stone in a line of
## them: a risky shortcut. It holds for HOLD seconds after the player lands on
## it (cracks glowing brighter, the slab shaking, a grinding crack), then drops
## into the bed. GONE_TIME later it rises again, glowing, and is solid after
## REFORM_TIME, but never into a player still in its column. Robots do not
## crack it and never path over it: the builder parents slabs to the level
## root, outside the navmesh region. The amber crack lines and edge trim set
## slabs apart from the walkways, and the first slab a player walks up to
## teaches the rule once per run. Node origin = the top face's centre.
## Def key `crumble_tiles` (level_builder `_build_crumble_tiles`).
## tests/crumble_tile_probe.

enum Phase { SOLID, CRACKING, GONE, REFORMING }

@export var size: float = 2.2       ## m, square
@export var thickness: float = 0.4
## Which authored line it belongs to (tests/crumble_tile_probe groups by it).
var line: int = 0

const HOLD := 0.7
const GONE_TIME := 3.5
const REFORM_TIME := 0.8
const DROP := 2.0              ## m the slab sinks out of sight
const FEET_ABOVE := 0.35       ## m above the top that still counts as standing on it
const BODY_R := 0.3
const TEACH_REACH := 9.0
const TEACH_TEXT := "CRUMBLING SLABS: they hold for a moment after you land, then drop into the slag. Keep moving."
const CRACK_COLOR := Color(1.0, 0.55, 0.15)
## The cracks are unshaded (emission energy does nothing), so the warning is a
## change of hue and width: amber -> white-hot, lines thickening, the slab body
## glowing from inside. A brighter amber read the same as an idle slab.
const HOT_COLOR := Color(1.0, 0.97, 0.75)
const ROCK_HOT := Color(1.0, 0.28, 0.04)

var phase: Phase = Phase.SOLID
var _t := 0.0
var _shape: CollisionShape3D
var _visual: Node3D
var _crack_mat: StandardMaterial3D
var _rock_mat: StandardMaterial3D
var _cracks: Array[MeshInstance3D] = []

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("hazard")
	_build()

func _build() -> void:
	_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size, thickness, size)
	_shape.shape = bs
	_shape.position = Vector3.DOWN * thickness * 0.5
	add_child(_shape)
	_visual = Node3D.new()
	add_child(_visual)
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size, thickness, size)
	slab.mesh = bm
	_rock_mat = StandardMaterial3D.new()
	_rock_mat.albedo_color = Color(0.16, 0.13, 0.12)
	_rock_mat.roughness = 0.95
	_rock_mat.emission_enabled = true
	_rock_mat.emission = Color.BLACK
	slab.material_override = _rock_mat
	slab.position = Vector3.DOWN * thickness * 0.5
	_visual.add_child(slab)
	_crack_mat = StandardMaterial3D.new()
	_crack_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack_mat.albedo_color = CRACK_COLOR
	_crack_mat.emission_enabled = true
	_crack_mat.emission = CRACK_COLOR
	_crack_mat.emission_energy_multiplier = 1.2
	# Crack lines across the top and a trim round the edge: the slab's tell.
	var lines := [
		[Vector3(0.0, 0.0, 0.0), Vector3(size * 0.8, 0.02, 0.06), 0.6],
		[Vector3(0.15, 0.0, 0.2), Vector3(size * 0.55, 0.02, 0.05), -0.9],
		[Vector3(-0.3, 0.0, -0.25), Vector3(size * 0.4, 0.02, 0.05), 1.6],
	]
	for l in lines:
		var c := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = l[1]
		c.mesh = cm
		c.material_override = _crack_mat
		c.position = l[0] + Vector3.UP * 0.011
		c.rotation.y = l[2]
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual.add_child(c)
		_cracks.append(c)
	for side in 4:
		var e := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = Vector3(size, 0.03, 0.08)
		e.mesh = em
		e.material_override = _crack_mat
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ang := side * PI * 0.5
		e.rotation.y = ang
		e.position = Vector3(sin(ang), 0.0, cos(ang)) * (size * 0.5 - 0.04) + Vector3.UP * 0.012
		_visual.add_child(e)

func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D

## Player feet over the slab's footprint, from `below` to FEET_ABOVE about the top.
func _over(p: Node3D, below: float) -> bool:
	if p == null:
		return false
	var local := p.global_position - global_position
	var half := size * 0.5 + BODY_R
	return absf(local.x) <= half and absf(local.z) <= half and local.y <= FEET_ABOVE and local.y >= -below

func _physics_process(delta: float) -> void:
	var p := _player()
	match phase:
		Phase.SOLID:
			if p and p.global_position.distance_to(global_position) <= TEACH_REACH:
				GameState.teach_once("crumble", TEACH_TEXT)
			if _over(p, 0.15):
				phase = Phase.CRACKING
				_t = 0.0
				AudioBus.play_synth_at("mech_step", global_position, -2.0, 0.55)
		Phase.CRACKING:
			_t += delta
			var k := clampf(_t / HOLD, 0.0, 1.0)
			_heat(k)
			_visual.position = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 0.045 * k
			if _t >= HOLD:
				phase = Phase.GONE
				_t = 0.0
				_shape.set_deferred("disabled", true)
				AudioBus.play_synth_at("explosion", global_position, -12.0, 1.7)
		Phase.GONE:
			_t += delta
			_visual.position = Vector3.DOWN * minf(DROP, _t * _t * 9.0)
			_visual.visible = _t < 0.6
			if _t >= GONE_TIME and not _over(p, 4.0):
				phase = Phase.REFORMING
				_t = 0.0
				_visual.visible = true
				_heat(1.0)
				AudioBus.play_synth_at("charge", global_position, -6.0, 0.6)
		Phase.REFORMING:
			_t += delta
			var r := clampf(_t / REFORM_TIME, 0.0, 1.0)
			_visual.position = Vector3.DOWN * DROP * (1.0 - r)
			_heat(1.0 - r)
			if _t >= REFORM_TIME:
				if _over(p, 4.0):
					return # someone climbed into the column: wait
				phase = Phase.SOLID
				_visual.position = Vector3.ZERO
				_heat(0.0)
				_shape.set_deferred("disabled", false)

## 0 = idle amber hairlines, 1 = white-hot gashes and a glowing slab.
func _heat(k: float) -> void:
	var c := CRACK_COLOR.lerp(HOT_COLOR, k)
	_crack_mat.albedo_color = c
	_crack_mat.emission = c
	for m in _cracks:
		m.scale = Vector3(1.0, 1.0, 1.0 + 2.5 * k)
	_rock_mat.emission = ROCK_HOT * (k * 0.9)
