class_name HoldZone
extends Area3D
## A large capture point you must HOLD GROUND in: progress fills only while the
## player stands inside the ring and drains fast the moment they leave — so you
## can't kite, you have to plant your feet and fight off the waves on the spot.
## Distinct from the small hack-console: a big, exposed arena objective.
## Completes its task at `hold_seconds`.

@export var task_id: String = "hold"
@export var hold_seconds: float = 12.0
@export var radius: float = 5.5
@export var accent: Color = Color(0.4, 0.85, 1.0)

var _done: bool = false
var _inside: int = 0
var _t: float = 0.0
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _column: MeshInstance3D
var _col_mat: StandardMaterial3D
var _light: OmniLight3D

func _ready() -> void:
	collision_layer = 64
	collision_mask = 2 # player
	add_to_group("objective")
	body_entered.connect(func(b): if b.is_in_group("player"): _inside += 1)
	body_exited.connect(func(b): if b.is_in_group("player"): _inside = maxi(0, _inside - 1))
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 5.0
	cs.shape = cyl
	cs.position = Vector3(0, 2.0, 0)
	add_child(cs)
	_build_visual()

func _build_visual() -> void:
	# Flat glowing ring painted on the floor marking the capture zone.
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.35
	tm.outer_radius = radius
	tm.rings = 48
	tm.ring_segments = 8
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.albedo_color = accent
	_ring_mat.emission_enabled = true
	_ring_mat.emission = accent
	_ring_mat.emission_energy_multiplier = 3.0
	tm.material = _ring_mat
	_ring.mesh = tm
	_ring.position = Vector3(0, 0.06, 0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	# A soft translucent column of light rising from the zone — a beacon you can
	# see across the arena and must get back to.
	_column = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.92
	cm.bottom_radius = radius * 0.92
	cm.height = 9.0
	cm.radial_segments = 32
	_col_mat = StandardMaterial3D.new()
	_col_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_col_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_col_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_col_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_col_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.06)
	_col_mat.emission_enabled = true
	_col_mat.emission = accent
	_col_mat.emission_energy_multiplier = 0.5
	cm.material = _col_mat
	_column.mesh = cm
	_column.position = Vector3(0, 4.5, 0)
	_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_column)

	_light = OmniLight3D.new()
	_light.light_color = accent
	_light.light_energy = 2.0
	_light.omni_range = radius * 2.2
	_light.position = Vector3(0, 2.0, 0)
	add_child(_light)

func _process(delta: float) -> void:
	_t += delta
	var prog := _task_progress()
	if not _done:
		if _inside > 0:
			GameState.advance_task(task_id, delta)
			if GameState.is_task_done(task_id):
				_on_complete()
		elif prog > 0.0:
			# Drains noticeably faster than it fills — leaving costs you.
			GameState.set_task_progress(task_id, maxf(0.0, prog - delta * 1.5))
	# Green-shift + pulse hard while held; cool blue and slow when contested/empty.
	var held := _inside > 0 and not _done
	var col := Color(0.4, 1.0, 0.5) if (held or _done) else accent
	var rate := 8.0 if held else 2.5
	var glow := 3.0 + (sin(_t * rate) * 1.5 if not _done else 2.0)
	if _ring_mat:
		_ring_mat.emission = col
		_ring_mat.emission_energy_multiplier = glow
	if _col_mat:
		_col_mat.emission = col
	if _light:
		_light.light_color = col
		_light.light_energy = 2.0 + sin(_t * rate) * 0.8

func _task_progress() -> float:
	for t in GameState.level_tasks:
		if t["id"] == task_id:
			return t["progress"]
	return 0.0

func _on_complete() -> void:
	_done = true
	if has_node("/root/AudioBus"):
		var ab: Node = get_node("/root/AudioBus")
		if ab.has_method("play_synth_at"):
			ab.play_synth_at("victory", global_position, -3.0, 1.1)
	# Triumphant flare on the captured zone.
	var tw := create_tween()
	tw.tween_property(_light, "light_energy", 6.0, 0.2)
	tw.tween_property(_light, "light_energy", 2.5, 0.4)
