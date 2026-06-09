class_name EnemyBrute
extends EnemyBase
## A heavy, slow shielded brute. Its big frontal slab soaks ~90% of damage from
## the front, so you have to flank it — shoot its sides or back. Closes in and
## slams in melee. Reads its shield clearly so the counterplay is obvious.

@export var slam_damage: float = 30.0
@export var block_factor: float = 0.1 ## Fraction of frontal damage that gets through.
@export var front_cone_dot: float = 0.4 ## How wide the shielded front arc is.

var _eye_mat: StandardMaterial3D
var _shield_mat: StandardMaterial3D
var _block_cd: float = 0.0

func _ready() -> void:
	_build_model()
	super._ready()
	max_health = 280.0
	move_speed = 2.9
	turn_speed = 3.2
	sight_range = 40.0
	sight_angle_deg = 200.0
	attack_range = 3.2
	preferred_range = 2.2
	attack_cooldown = 1.7
	score_value = 320
	stagger_threshold = 100000.0 # immovable
	flinch_knockback = 0.0
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 3.0

func _build_model() -> void:
	var model := Node3D.new()
	model.name = "Model"
	add_child(model)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.13, 0.14, 0.16)
	dark.metallic = 0.6
	dark.roughness = 0.5
	# Bulky torso.
	var torso := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(1.1, 1.2, 0.75)
	torso.mesh = tm
	torso.material_override = dark
	torso.position = Vector3(0, 1.2, 0)
	model.add_child(torso)
	# Squat legs.
	for sx in [-0.34, 0.34]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.38, 1.0, 0.45)
		leg.mesh = lm
		leg.material_override = dark
		leg.position = Vector3(sx, 0.5, 0)
		model.add_child(leg)
	# Head + eye.
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.5, 0.45, 0.5)
	head.mesh = hm
	head.material_override = dark
	head.position = Vector3(0, 1.95, 0)
	model.add_child(head)
	var eyem := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(0.34, 0.08, 0.05)
	eyem.mesh = em
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.emission_enabled = true
	_eye_mat.albedo_color = Color(1.0, 0.25, 0.12)
	_eye_mat.emission = Color(1.0, 0.3, 0.15)
	_eye_mat.emission_energy_multiplier = 5.0
	eyem.material_override = _eye_mat
	eyem.position = Vector3(0, 1.95, -0.26)
	model.add_child(eyem)
	# The big frontal shield slab (faces local -Z, the enemy's front).
	var shield := MeshInstance3D.new()
	var shm := BoxMesh.new()
	shm.size = Vector3(1.5, 1.7, 0.16)
	shield.mesh = shm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.18, 0.2, 0.24)
	smat.metallic = 0.8
	smat.roughness = 0.3
	shield.material_override = smat
	shield.position = Vector3(0, 1.2, -0.62)
	model.add_child(shield)
	# Glowing shield rim so the protected face reads at a glance.
	var rim := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(1.62, 1.82, 0.06)
	rim.mesh = rm
	_shield_mat = StandardMaterial3D.new()
	_shield_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shield_mat.albedo_color = Color(0.3, 0.7, 1.0, 0.5)
	_shield_mat.emission_enabled = true
	_shield_mat.emission = Color(0.35, 0.75, 1.0)
	_shield_mat.emission_energy_multiplier = 2.5
	rim.material_override = _shield_mat
	rim.position = Vector3(0, 1.2, -0.68)
	model.add_child(rim)

	var eye_node := Node3D.new()
	eye_node.name = "Eye"
	eye_node.position = Vector3(0, 1.95, -0.3)
	add_child(eye_node)
	eye = eye_node

## Frontal shield: damage hitting the front arc is mostly absorbed. Flank it.
func modify_incoming_damage(amount: float, source: Node) -> float:
	if source is Node3D:
		var to: Vector3 = (source as Node3D).global_position - global_position
		to.y = 0.0
		if to.length() > 0.1:
			var fwd := -global_transform.basis.z
			fwd.y = 0.0
			if fwd.normalized().dot(to.normalized()) > front_cone_dot:
				_shield_spark()
				return amount * block_factor
	return amount

func _shield_spark() -> void:
	if _block_cd > 0.0:
		return
	_block_cd = 0.08
	if _shield_mat:
		_shield_mat.emission_energy_multiplier = 9.0
	if has_node("/root/AudioBus"):
		AudioBus.play_synth_at("impact_metal", global_position - global_transform.basis.z * 0.7, -2.0, 0.7)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _block_cd > 0.0:
		_block_cd = maxf(0.0, _block_cd - delta)
	elif _shield_mat:
		_shield_mat.emission_energy_multiplier = move_toward(_shield_mat.emission_energy_multiplier, 2.5, delta * 18.0)

func _perform_attack() -> void:
	if target == null:
		return
	if global_position.distance_to(target.global_position) <= attack_range:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(slam_damage, self)
		recoil = 1.0
		AudioBus.play_synth_at("mech_step", global_position, 2.0, 0.6)
		if target is CharacterBody3D:
			var away := (target.global_position - global_position)
			away.y = 0.0
			(target as CharacterBody3D).velocity += away.normalized() * 8.0 + Vector3.UP * 2.0
