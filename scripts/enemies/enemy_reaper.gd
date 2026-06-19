class_name EnemyReaper
extends EnemyBase
## Fast melee killer: a gaunt bipedal frame with two long scythe-blades for arms.
## Sprints at the player and lunges into a slashing strike. Fragile but lethal up
## close. Built from procedural primitives.

@export var slash_damage: float = 22.0

var _eye_mat: StandardMaterial3D
var _arms: Array[Node3D] = []


func _ready() -> void:
	max_health = 62.0
	move_speed = 8.6
	turn_speed = 9.0
	sight_range = 34.0
	sight_angle_deg = 200.0
	attack_range = 3.0
	preferred_range = 1.5
	attack_cooldown = 1.1
	attack_lunge_speed = 12.0
	score_value = 130
	stagger_threshold = 40.0
	super._ready()
	_build_model()


func _build_model() -> void:
	var model: Node3D = get_node_or_null("Model")
	if model == null:
		model = Node3D.new()
		model.name = "Model"
		add_child(model)

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.1, 0.12)
	dark.metallic = 0.8
	dark.roughness = 0.35
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.62, 0.64, 0.68)
	blade_mat.metallic = 0.95
	blade_mat.roughness = 0.18
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(1.0, 0.2, 0.14)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(1.0, 0.2, 0.1)
	_eye_mat.emission_energy_multiplier = 3.0

	var torso := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.4, 0.72, 0.26)
	tm.material = dark
	torso.mesh = tm
	torso.position.y = 1.02
	model.add_child(torso)

	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.22, 0.22, 0.24)
	hm.material = dark
	head.mesh = hm
	head.position.y = 1.5
	model.add_child(head)

	var eye := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(0.18, 0.05, 0.05)
	em.material = _eye_mat
	eye.mesh = em
	eye.position = Vector3(0, 1.5, -0.13)
	model.add_child(eye)

	for sx in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.1, 0.86, 0.1)
		lm.material = dark
		leg.mesh = lm
		leg.position = Vector3(sx * 0.12, 0.43, 0)
		model.add_child(leg)

	# Two long scythe-blade arms angled forward like a mantis.
	for sx in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(sx * 0.3, 1.18, 0)
		model.add_child(arm)
		var upper := MeshInstance3D.new()
		var um := BoxMesh.new()
		um.size = Vector3(0.08, 0.08, 0.5)
		um.material = dark
		upper.mesh = um
		upper.position = Vector3(0, 0, -0.22)
		arm.add_child(upper)
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.04, 0.46, 1.15)
		bm.material = blade_mat
		blade.mesh = bm
		blade.position = Vector3(0, -0.08, -0.75)
		blade.rotation = Vector3(deg_to_rad(-28), 0, 0)
		arm.add_child(blade)
		_arms.append(arm)


func _process(_delta: float) -> void:
	# Raise the blades when closing for the kill.
	var lift := -0.5 if is_enraged() else 0.0
	for a in _arms:
		a.rotation.x = lerpf(a.rotation.x, lift, 0.15)


func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= attack_range * 1.4:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(slash_damage, self)
		AudioBus.play_synth_at("impact_metal", global_position, -6.0, 1.6)
	_attack_lunge()
