class_name EnemyBrute
extends EnemyBase
## A heavy, slow shielded brute. Its big frontal slab soaks ~90% of damage from
## the front, so you have to flank it — shoot its sides or back. Closes in and
## slams in melee. Reads its shield clearly so the counterplay is obvious.

@export var slam_damage: float = 30.0
@export var block_factor: float = 0.1 ## Fraction of frontal damage that gets through.
@export var front_cone_dot: float = 0.4 ## How wide the shielded front arc is.

var _shield_mat: StandardMaterial3D
var _block_cd: float = 0.0

func _ready() -> void:
	_build_shield()
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

## The chassis itself is the imported "Mike" heavy mech ($Model in the scene);
## only the gameplay-critical frontal shield slab + glowing rim are code-built,
## bolted to the body so the protected arc reads at a glance.
func _build_shield() -> void:
	var rig := Node3D.new()
	rig.name = "ShieldRig"
	add_child(rig)
	# The big frontal shield slab (faces local -Z, the enemy's front).
	var shield := MeshInstance3D.new()
	var shm := BeveledBoxMesh.new()
	shm.size = Vector3(1.6, 1.8, 0.16)
	shm.bevel = 0.04
	shield.mesh = shm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.18, 0.2, 0.24)
	smat.metallic = 0.8
	smat.roughness = 0.3
	shield.material_override = smat
	shield.position = Vector3(0, 1.3, -0.8)
	rig.add_child(shield)
	# Glowing shield rim so the protected face reads at a glance.
	var rim := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(1.72, 1.92, 0.06)
	rim.mesh = rm
	_shield_mat = StandardMaterial3D.new()
	_shield_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shield_mat.albedo_color = Color(0.3, 0.7, 1.0, 0.5)
	_shield_mat.emission_enabled = true
	_shield_mat.emission = Color(0.35, 0.75, 1.0)
	_shield_mat.emission_energy_multiplier = 2.5
	rim.material_override = _shield_mat
	rim.position = Vector3(0, 1.3, -0.86)
	rig.add_child(rim)

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
