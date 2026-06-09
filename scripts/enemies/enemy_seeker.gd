class_name EnemySeeker
extends EnemyBase
## A fast, fragile kamikaze flyer. It doesn't shoot — it locks on, screams in at
## the player's height, and detonates on contact (or when shot down). A blinking
## core pulses faster the closer it gets, telegraphing the blast so you can pop
## it or dodge in time.

@export var intercept_height: float = 1.0 ## Flies toward the player's chest height.
@export var detonate_radius: float = 2.2
@export var blast_radius: float = 4.2
@export var blast_damage: float = 48.0

const BIG_BLAST := preload("res://scenes/fx/grenade_explosion.tscn")

var _detonated: bool = false
var _eye_light: OmniLight3D
var _core_mat: StandardMaterial3D
var _pulse: float = 0.0

func _ready() -> void:
	max_health = 28.0
	move_speed = 9.5
	turn_speed = 10.0
	sight_range = 40.0
	sight_angle_deg = 200.0
	attack_range = 30.0
	preferred_range = 0.5
	attack_cooldown = 1.0
	score_value = 90
	stagger_threshold = 99999.0 # too fast/fragile to bother staggering
	_build_model()
	super._ready()

func _build_model() -> void:
	var model := Node3D.new()
	model.name = "Model"
	add_child(model)
	# Dark armoured core.
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.64
	core.mesh = sm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.1, 0.1, 0.12)
	cmat.metallic = 0.7
	cmat.roughness = 0.4
	core.material_override = cmat
	core.position = Vector3(0, 1.0, 0)
	model.add_child(core)
	# Warning spikes.
	for a in [0.0, TAU / 3.0, 2.0 * TAU / 3.0]:
		var spike := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, 0.06, 0.4)
		spike.mesh = bm
		spike.material_override = cmat
		spike.position = Vector3(sin(a) * 0.3, 1.0, cos(a) * 0.3)
		spike.rotation = Vector3(0, a, 0) # box's local -Z points radially outward
		model.add_child(spike)
	# Blinking red eye.
	var eyem := MeshInstance3D.new()
	var esm := SphereMesh.new()
	esm.radius = 0.13
	esm.height = 0.26
	eyem.mesh = esm
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.emission_enabled = true
	_core_mat.albedo_color = Color(1.0, 0.2, 0.12)
	_core_mat.emission = Color(1.0, 0.25, 0.15)
	_core_mat.emission_energy_multiplier = 4.0
	eyem.material_override = _core_mat
	eyem.position = Vector3(0, 1.0, 0.28)
	model.add_child(eyem)

	var eye_node := Node3D.new()
	eye_node.name = "Eye"
	eye_node.position = Vector3(0, 1.0, 0.3)
	add_child(eye_node)
	eye = eye_node

	_eye_light = OmniLight3D.new()
	_eye_light.light_color = Color(1.0, 0.25, 0.15)
	_eye_light.light_energy = 2.0
	_eye_light.omni_range = 4.0
	_eye_light.position = Vector3(0, 1.0, 0)
	add_child(_eye_light)

func _apply_gravity(_delta: float) -> void:
	pass # it flies

# Rush straight at the target instead of holding at a range.
func _state_chase(delta: float) -> void:
	if target == null:
		set_state(State.IDLE)
		return
	_move_toward(target.global_position, delta)

func _state_attack(delta: float) -> void:
	_state_chase(delta)

func _move_toward(dest: Vector3, delta: float) -> void:
	var ty: float = (target.global_position.y if target else dest.y) + intercept_height
	var to := Vector3(dest.x, ty, dest.z) - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var spd := chase_speed()
	if flat.length() > 0.05:
		var d := flat.normalized()
		velocity.x = move_toward(velocity.x, d.x * spd, 16.0 * delta)
		velocity.z = move_toward(velocity.z, d.z * spd, 16.0 * delta)
		_face_dir(d, delta)
	velocity.y = move_toward(velocity.y, (ty - global_position.y) * 5.0, 30.0 * delta)

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	super._physics_process(delta)
	# Blink faster as it closes in.
	if target and _core_mat:
		var dist := global_position.distance_to(target.global_position)
		_pulse += delta * clampf(14.0 - dist, 3.0, 22.0)
		var b := 0.6 + 0.4 * sin(_pulse)
		_core_mat.emission_energy_multiplier = (3.0 + 8.0 * (1.0 - clampf(dist / 8.0, 0.0, 1.0))) * b
		if _eye_light:
			_eye_light.light_energy = 2.0 + 3.0 * b
	_check_detonate()

func _check_detonate() -> void:
	if _detonated or target == null:
		return
	if global_position.distance_to(target.global_position) <= detonate_radius:
		_detonate(true)

## Boom. `hit_player` true on a kamikaze run (full damage); false when shot down.
func _detonate(hit_player: bool) -> void:
	if _detonated:
		return
	_detonated = true
	var scene := get_tree().current_scene
	if scene:
		var fx := BIG_BLAST.instantiate()
		scene.add_child(fx)
		(fx as Node3D).global_position = global_position
	if has_node("/root/AudioBus"):
		AudioBus.play_synth_at("explosion", global_position, 5.0, 0.7)
	# AoE: hurt the player + any nearby machines.
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = blast_radius
	q.shape = sh
	q.transform = Transform3D(Basis(), global_position)
	q.collision_mask = 0b0000111 # world + player + enemy
	var seen := {}
	for h in space.intersect_shape(q, 16):
		var col: Node = h.get("collider")
		if col == null or col == self:
			continue
		var d = col.get_node_or_null("Damageable")
		if d == null or seen.has(d):
			continue
		seen[d] = true
		var dist: float = (col as Node3D).global_position.distance_to(global_position) if col is Node3D else 0.0
		var falloff := clampf(1.0 - dist / blast_radius, 0.0, 1.0)
		d.apply_damage(blast_damage * falloff, self)
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		var pd: float = (p as Node3D).global_position.distance_to(global_position)
		if pd < blast_radius * 2.0:
			p.shake(clampf(1.0 - pd / (blast_radius * 2.0), 0.0, 1.0))
	queue_free()

# Shot down before it reaches you -> it still goes off (smaller, no free kill at point-blank).
func _on_died(source: Node) -> void:
	if _detonated:
		return
	GameState.add_kill(score_value, _kill_label())
	state = State.DEAD
	set_physics_process(false)
	_detonate(false)
