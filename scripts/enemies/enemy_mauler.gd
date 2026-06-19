class_name EnemyMauler
extends EnemyBase
## Heavy melee brawler: a slab-bodied walker with two oversized hammer-fists. Slow
## but very tough; closes in and slams. Procedural build.

@export var slam_damage: float = 34.0

var _eye_mat: StandardMaterial3D
var _fists: Array[Node3D] = []
var _swing: float = 0.0


func _ready() -> void:
	max_health = 210.0
	move_speed = 5.0
	turn_speed = 5.5
	sight_range = 32.0
	sight_angle_deg = 180.0
	attack_range = 3.6
	preferred_range = 1.8
	attack_cooldown = 1.5
	attack_lunge_speed = 9.0
	score_value = 175
	stagger_threshold = 130.0
	super._ready()
	_build_model()


func _build_model() -> void:
	var model: Node3D = get_node_or_null("Model")
	if model == null:
		model = Node3D.new()
		model.name = "Model"
		add_child(model)

	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.34, 0.3, 0.26)
	hull.metallic = 0.7
	hull.roughness = 0.45
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.09, 0.09)
	dark.metallic = 0.8
	dark.roughness = 0.4
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(1.0, 0.45, 0.1)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(1.0, 0.4, 0.05)
	_eye_mat.emission_energy_multiplier = 3.0

	var torso := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.85, 0.9, 0.55)
	tm.material = hull
	torso.mesh = tm
	torso.position.y = 1.25
	model.add_child(torso)

	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.34, 0.3, 0.34)
	hm.material = dark
	head.mesh = hm
	head.position.y = 1.82
	model.add_child(head)

	var eye := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(0.28, 0.07, 0.05)
	em.material = _eye_mat
	eye.mesh = em
	eye.position = Vector3(0, 1.82, -0.17)
	model.add_child(eye)

	for sx in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.24, 1.0, 0.26)
		lm.material = dark
		leg.mesh = lm
		leg.position = Vector3(sx * 0.24, 0.5, 0)
		model.add_child(leg)

	# Two huge hammer-fist arms.
	for sx in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(sx * 0.55, 1.45, 0)
		model.add_child(arm)
		var upper := MeshInstance3D.new()
		var um := BoxMesh.new()
		um.size = Vector3(0.16, 0.16, 0.55)
		um.material = dark
		upper.mesh = um
		upper.position = Vector3(0, -0.1, -0.25)
		arm.add_child(upper)
		var fist := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.42, 0.42, 0.42)
		fm.material = hull
		fist.mesh = fm
		fist.position = Vector3(0, -0.18, -0.6)
		arm.add_child(fist)
		_fists.append(arm)


func _process(delta: float) -> void:
	# Heave the fists up when winding into the slam.
	_swing = move_toward(_swing, recoil, delta * 6.0)
	for f in _fists:
		f.rotation.x = lerpf(f.rotation.x, -0.9 * _swing, 0.25)


func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= attack_range * 1.4:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(slam_damage, self)
		AudioBus.play_synth_at("impact_metal", global_position, -4.0, 1.2)
	_attack_lunge()
