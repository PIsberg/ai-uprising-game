class_name TargetDummy
extends StaticBody3D
## Firing-range pop-up target: a humanoid silhouette board with emissive
## bullseye rings on a post. Shootable like any Damageable (hit markers and
## damage numbers come for free); on a kill it sparks, topples backward, then
## pops back up a moment later with full health. Optionally slides side to
## side for tracking practice. Builds all of its visuals in code.

@export var max_health: float = 60.0
@export var respawn_seconds: float = 2.0
@export var move_range: float = 0.0 ## Half-width of the side-to-side patrol (0 = static).
@export var move_speed: float = 1.2
@export var accent: Color = Color(1.0, 0.45, 0.15)

var hp: Damageable
var _board: Node3D
var _rings: Array[StandardMaterial3D] = []
var _down: bool = false
var _home_x: float = 0.0
var _t: float = randf() * TAU

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_home_x = position.x
	_build_visuals()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.9, 0.25)
	shape.shape = box
	shape.position = Vector3(0, 1.15, 0)
	add_child(shape)
	hp = Damageable.new()
	hp.name = "Damageable"
	hp.max_health = max_health
	add_child(hp)
	hp.died.connect(_on_died)
	hp.damaged.connect(_on_damaged)

func _build_visuals() -> void:
	_board = Node3D.new()
	_board.position = Vector3(0, 0.25, 0) # hinge at the post top
	add_child(_board)
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.05
	pm.bottom_radius = 0.07
	pm.height = 0.5
	pm.radial_segments = 8
	pm.material = _flat(Color(0.25, 0.26, 0.3), 0.6)
	post.mesh = pm
	post.position = Vector3(0, 0.25, 0)
	add_child(post)
	# Silhouette: torso slab + head, the classic range-target shape.
	var torso := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.74, 1.2, 0.08)
	tm.material = _flat(Color(0.16, 0.17, 0.2), 0.85)
	torso.mesh = tm
	torso.position = Vector3(0, 0.85, 0)
	_board.add_child(torso)
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.36, 0.4, 0.08)
	hm.material = tm.material
	head.mesh = hm
	head.position = Vector3(0, 1.66, 0)
	_board.add_child(head)
	# Concentric emissive bullseye rings on the chest.
	for i in 3:
		var ring := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.3 - i * 0.1
		rm.bottom_radius = rm.top_radius
		rm.height = 0.012
		rm.radial_segments = 20
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = accent if i % 2 == 0 else Color(0.92, 0.92, 0.9)
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = 1.4
		rm.material = mat
		_rings.append(mat)
		ring.mesh = rm
		ring.rotation.x = PI * 0.5 # face the shooter
		ring.position = Vector3(0, 0.9, 0.047 + i * 0.012)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_board.add_child(ring)

func _flat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = 0.3
	return m

func _process(delta: float) -> void:
	if move_range <= 0.0 or _down:
		return
	_t += delta * move_speed
	position.x = _home_x + sin(_t) * move_range

## Bright ring blink on every hit so the target visibly registers.
func _on_damaged(_amount: float, _source: Node) -> void:
	for m in _rings:
		m.emission_energy_multiplier = 5.0
	var tw := create_tween().set_parallel(true)
	for m in _rings:
		tw.tween_property(m, "emission_energy_multiplier", 1.4, 0.18)

func _on_died(_source: Node) -> void:
	if _down:
		return
	_down = true
	collision_layer = 0 # can't be hit while down
	AudioBus.play_synth_at("impact_metal", global_position, 1.0, 0.65)
	_spark_burst()
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tw.tween_property(_board, "rotation:x", -PI * 0.48, 0.3)
	tw.tween_interval(respawn_seconds)
	# Pop back up with a little overshoot, then re-arm.
	tw.tween_property(_board, "rotation:x", 0.06, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_board, "rotation:x", 0.0, 0.1)
	tw.tween_callback(_respawn)

func _respawn() -> void:
	hp.current_health = hp.max_health
	hp.health_changed.emit(hp.current_health, hp.max_health)
	collision_layer = 1
	_down = false

func _spark_burst() -> void:
	var p := CPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 14
	p.lifetime = 0.5
	p.local_coords = false
	p.direction = Vector3(0, 0.6, 1.0)
	p.spread = 50.0
	p.gravity = Vector3(0, -14, 0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.9
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.03, 0.1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = accent
	mat.emission_enabled = true
	mat.emission = accent
	mat.emission_energy_multiplier = 4.0
	mesh.material = mat
	p.mesh = mesh
	add_child(p)
	p.position = Vector3(0, 1.1, 0.1)
	var t := get_tree().create_timer(1.0)
	t.timeout.connect(p.queue_free)
