class_name LadleCrane
# @lat: [[level-system#Ladle Cranes]]
extends Node3D
## The foundry's overhead crane, and it is hunting you. A bridge crane rides
## two runway rails under the roof across its coverage (`span_x` by `span_z`,
## world metres); its trolley carries a ladle of molten metal on a cable. It
## travels to where the player stands, stops, lights a warning ring on the
## floor under the ladle and tilts it for `aim_time`, then pours: a molten pool
## (LavaHazard, burns the player only) that cools away after `pool_time`. One
## pour every `period` seconds, and only on a player inside its coverage.
## Def key `ladle_crane` (level_builder `_build_ladle_crane`). tests/ladle_crane_probe.

signal poured(at: Vector3)

@export var span_x: Vector2 = Vector2(-10, 10) ## world x range the trolley covers
@export var span_z: Vector2 = Vector2(-10, 10) ## world z range
@export var height: float = 10.0               ## runway rail height
@export var speed: float = 4.0                 ## m/s, bridge and trolley
@export var aim_time: float = 1.4              ## s of warning before it pours
@export var period: float = 8.0                ## s between pours
@export var first_pour: float = 4.0            ## s before the first pour
@export var pool_size: float = 4.5             ## m across the molten pool
@export var pool_time: float = 6.0             ## s before the pool cools away
@export var pool_dmg: float = 14.0             ## burn per tick (LavaHazard tick)

const LADLE_RADIUS := 0.9
const LADLE_DROP := 4.2   ## m from the rails down to the ladle's rim
const REACH := 3.0        ## m outside the coverage a player still counts as inside

var aiming := false
var _xz := Vector2.ZERO
var _cd := 0.0
var _aim_t := 0.0
var _bridge: MeshInstance3D
var _trolley: Node3D
var _ladle: Node3D
var _cable: MeshInstance3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _stream: MeshInstance3D

func _ready() -> void:
	_xz = Vector2((span_x.x + span_x.y) * 0.5, (span_z.x + span_z.y) * 0.5)
	_cd = first_pour
	_build()
	_place()

## The ladle's rim centre, world.
func ladle_position() -> Vector3:
	return Vector3(_xz.x, height - LADLE_DROP, _xz.y)

func _build() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.2, 0.19, 0.18)
	steel.metallic = 0.7
	steel.roughness = 0.5
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.9, 0.62, 0.08)
	paint.roughness = 0.6
	var len_x := span_x.y - span_x.x + 4.0
	var len_z := span_z.y - span_z.x + 4.0
	var cx := (span_x.x + span_x.y) * 0.5
	for z: float in [span_z.x - 2.0, span_z.y + 2.0]:
		_box(self, Vector3(cx, height, z), Vector3(len_x, 0.5, 0.5), steel)
	_bridge = _box(self, Vector3.ZERO, Vector3(0.8, 0.7, len_z), paint)
	_trolley = Node3D.new()
	add_child(_trolley)
	_box(_trolley, Vector3(0, -0.45, 0), Vector3(1.6, 0.6, 1.4), steel)
	_cable = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.04
	cm.height = 1.0
	_cable.mesh = cm
	_cable.material_override = steel
	_trolley.add_child(_cable)
	_ladle = Node3D.new()
	_trolley.add_child(_ladle)
	_ladle.position = Vector3(0, -LADLE_DROP, 0)
	var bucket := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = LADLE_RADIUS
	bm.bottom_radius = LADLE_RADIUS * 0.75
	bm.height = 1.3
	bucket.mesh = bm
	bucket.material_override = steel
	bucket.position = Vector3(0, -0.65, 0)
	_ladle.add_child(bucket)
	# A white-hot band round the lip so the ladle reads against a dark roof.
	var lip := MeshInstance3D.new()
	var lm := TorusMesh.new()
	lm.inner_radius = LADLE_RADIUS - 0.08
	lm.outer_radius = LADLE_RADIUS + 0.06
	lip.mesh = lm
	var lip_mat := StandardMaterial3D.new()
	lip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lip_mat.albedo_color = Color(1.0, 0.7, 0.3)
	lip_mat.emission_enabled = true
	lip_mat.emission = Color(1.0, 0.6, 0.2)
	lip_mat.emission_energy_multiplier = 4.0
	lip.material_override = lip_mat
	_ladle.add_child(lip)
	var melt := MeshInstance3D.new()
	var mm := CylinderMesh.new()
	mm.top_radius = LADLE_RADIUS * 0.9
	mm.bottom_radius = LADLE_RADIUS * 0.9
	mm.height = 0.05
	melt.mesh = mm
	var hot := StandardMaterial3D.new()
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hot.albedo_color = Color(1.0, 0.45, 0.1)
	hot.emission_enabled = true
	hot.emission = Color(1.0, 0.45, 0.1)
	hot.emission_energy_multiplier = 3.0
	melt.material_override = hot
	melt.position = Vector3(0, -0.06, 0)
	_ladle.add_child(melt)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.5, 0.2)
	glow.light_energy = 3.0
	glow.omni_range = 9.0
	glow.position = Vector3(0, -0.4, 0)
	_ladle.add_child(glow)
	# The pour: a glowing column from the ladle's lip to the floor.
	_stream = MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.22
	sm.bottom_radius = 0.35
	sm.height = 1.0
	_stream.mesh = sm
	_stream.material_override = hot
	_stream.visible = false
	add_child(_stream)
	# The warning ring on the floor under the ladle.
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = pool_size * 0.5 - 0.25
	tm.outer_radius = pool_size * 0.5
	_ring.mesh = tm
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(1.0, 0.25, 0.05, 0.0)
	_ring.material_override = _ring_mat
	_ring.scale = Vector3(1, 0.1, 1)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

func _box(parent: Node3D, pos: Vector3, sz: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _place() -> void:
	_bridge.position = Vector3(_xz.x, height - 0.1, (span_z.x + span_z.y) * 0.5)
	_trolley.position = Vector3(_xz.x, height, _xz.y)
	var drop := LADLE_DROP
	_cable.scale = Vector3(1, drop, 1)
	_cable.position = Vector3(0, -drop * 0.5, 0)

func _player_xz() -> Variant:
	var pl := GameState.nearest_player(global_position)
	if pl == null:
		return null
	var p := Vector2(pl.global_position.x, pl.global_position.z)
	if p.x < span_x.x - REACH or p.x > span_x.y + REACH or p.y < span_z.x - REACH or p.y > span_z.y + REACH:
		return null
	return Vector2(clampf(p.x, span_x.x, span_x.y), clampf(p.y, span_z.x, span_z.y))

func _physics_process(delta: float) -> void:
	if aiming:
		_aim_t -= delta
		var f := 1.0 - _aim_t / aim_time
		_ladle.rotation.z = lerpf(0.0, 0.55, f)
		_ring_mat.albedo_color.a = 0.35 + 0.45 * absf(sin(f * TAU * 3.0))
		if _aim_t <= 0.0:
			_pour()
		return
	_cd -= delta
	_ladle.rotation.z = move_toward(_ladle.rotation.z, 0.0, delta * 0.8)
	var want: Variant = _player_xz()
	if want != null:
		_xz = _xz.move_toward(want, speed * delta)
		_place()
		if _cd <= 0.0 and _xz.distance_to(want) < 0.5:
			aiming = true
			_aim_t = aim_time
			_ring.position = Vector3(_xz.x, 0.06, _xz.y)
			AudioBus.play_synth_at("charge", ladle_position(), -2.0, 0.5)

func _pour() -> void:
	aiming = false
	_cd = period
	_ring_mat.albedo_color.a = 0.0
	var at := Vector3(_xz.x, 0.0, _xz.y)
	var pool := LavaHazard.new()
	pool.size = Vector2(pool_size, pool_size)
	pool.damage_per_tick = pool_dmg
	pool.shore = false
	pool.melts_robots = false # a trap set for the player; the robots chasing it wade through
	# Fresh metal, brighter than the level's own beds, with the hazard border.
	pool.recolor = true
	pool.hazard_color = Color(1.0, 0.72, 0.22)
	pool.add_to_group("ladle_pool")
	var scene := get_tree().current_scene if get_tree().current_scene else get_parent()
	scene.add_child(pool)
	pool.global_position = at
	get_tree().create_timer(pool_time, false, true).timeout.connect(func() -> void:
		if is_instance_valid(pool):
			pool.remove_from_group("ladle_pool")
			pool.queue_free())
	var top := ladle_position().y
	_stream.scale = Vector3(1, top, 1)
	_stream.position = Vector3(_xz.x, top * 0.5, _xz.y)
	_stream.visible = true
	get_tree().create_timer(0.6, false, true).timeout.connect(func() -> void: _stream.visible = false)
	AudioBus.play_synth_at("lava_loop", at, -6.0, 1.0)
	AudioBus.play_synth_at("explosion", at, -10.0, 0.5)
	poured.emit(at)
