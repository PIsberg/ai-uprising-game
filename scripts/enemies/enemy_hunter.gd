class_name EnemyHunter
extends EnemyBase
## Sleek, fast skirmisher with twin shoulder cannons. Circle-strafes at mid range
## and fires rapid bolt bursts. Procedural build.

@export var proj_speed: float = 46.0
@export var proj_damage: float = 7.0
@export var burst_count: int = 3

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")

var _burst_left: int = 0
var _burst_t: float = 0.0
var _eye_mat: StandardMaterial3D


func _ready() -> void:
	max_health = 72.0
	move_speed = 7.6
	turn_speed = 8.0
	sight_range = 38.0
	sight_angle_deg = 200.0
	attack_range = 26.0
	preferred_range = 16.0
	attack_cooldown = 1.6
	score_value = 120
	stagger_threshold = 45.0
	super._ready()
	_build_model()


func _build_model() -> void:
	var model: Node3D = get_node_or_null("Model")
	if model == null:
		model = Node3D.new()
		model.name = "Model"
		add_child(model)

	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.26, 0.3, 0.36)
	shell.metallic = 0.7
	shell.roughness = 0.3
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.11, 0.13)
	dark.metallic = 0.8
	dark.roughness = 0.4
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(1.0, 0.55, 0.1)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(1.0, 0.5, 0.05)
	_eye_mat.emission_energy_multiplier = 2.8

	var torso := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.5, 0.5, 0.32)
	tm.material = shell
	torso.mesh = tm
	torso.position.y = 1.05
	model.add_child(torso)

	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.3, 0.18, 0.3)
	hm.material = dark
	head.mesh = hm
	head.position.y = 1.38
	model.add_child(head)

	var visor := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(0.26, 0.06, 0.05)
	vm.material = _eye_mat
	visor.mesh = vm
	visor.position = Vector3(0, 1.38, -0.15)
	model.add_child(visor)

	# Reverse-jointed legs.
	for sx in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.12, 0.9, 0.12)
		lm.material = dark
		leg.mesh = lm
		leg.position = Vector3(sx * 0.16, 0.45, 0.04)
		leg.rotation = Vector3(deg_to_rad(8.0), 0, 0)
		model.add_child(leg)

	# Twin shoulder cannons (the muzzle node sits between them).
	for sx in [-1.0, 1.0]:
		var cannon := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.1, 0.12, 0.46)
		cm.material = dark
		cannon.mesh = cm
		cannon.position = Vector3(sx * 0.32, 1.22, -0.12)
		model.add_child(cannon)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	super._physics_process(delta)
	if _burst_left > 0:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_fire_one()
			_burst_left -= 1
			_burst_t = 0.1


func _perform_attack() -> void:
	if target == null or _burst_left > 0:
		return
	_burst_left = burst_count
	_burst_t = 0.0


func _fire_one() -> void:
	if target == null or not is_instance_valid(target):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var origin: Vector3 = muzzle.global_position if muzzle else global_position + Vector3.UP
	var proj := PROJECTILE.instantiate()
	scene.add_child(proj)
	(proj as Node3D).global_position = origin
	var dir := (target.global_position + Vector3.UP * 0.5 - origin).normalized()
	dir = scatter_aim(dir, 2.5)
	if proj.has_method("launch"):
		proj.launch(dir * proj_speed, self, proj_damage, 0.0, 0.0)
	recoil = 1.0
	_muzzle_flash()
