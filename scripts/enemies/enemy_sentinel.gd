class_name EnemySentinel
extends EnemyBase
## Heavy four-legged weapons platform. Slow and very tanky; plants itself at
## range and lobs heavy bolts. A walking gun emplacement. Procedural build.

@export var proj_speed: float = 34.0
@export var proj_damage: float = 16.0

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")

var _eye_mat: StandardMaterial3D
var _cannon: Node3D


func _ready() -> void:
	max_health = 185.0
	move_speed = 3.4
	turn_speed = 4.0
	sight_range = 42.0
	sight_angle_deg = 180.0
	attack_range = 34.0
	preferred_range = 22.0
	attack_cooldown = 1.9
	score_value = 180
	stagger_threshold = 120.0
	super._ready()
	_build_model()


func _build_model() -> void:
	var model: Node3D = get_node_or_null("Model")
	if model == null:
		model = Node3D.new()
		model.name = "Model"
		add_child(model)

	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.3, 0.32, 0.34)
	hull.metallic = 0.75
	hull.roughness = 0.35
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.1, 0.12)
	dark.metallic = 0.8
	dark.roughness = 0.4
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = Color(1.0, 0.25, 0.18)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(1.0, 0.2, 0.1)
	_eye_mat.emission_energy_multiplier = 3.0

	# Squat hex turret body.
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.55
	bm.bottom_radius = 0.7
	bm.height = 0.55
	bm.radial_segments = 6
	bm.material = hull
	body.mesh = bm
	body.position.y = 1.0
	model.add_child(body)

	# Eye band.
	var eye := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(0.5, 0.1, 0.06)
	em.material = _eye_mat
	eye.mesh = em
	eye.position = Vector3(0, 1.05, -0.55)
	model.add_child(eye)

	# Big forward cannon on a yoke.
	_cannon = Node3D.new()
	_cannon.position = Vector3(0, 1.05, 0)
	model.add_child(_cannon)
	var barrel := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.22, 0.22, 0.95)
	cm.material = dark
	barrel.mesh = cm
	barrel.position = Vector3(0, 0, -0.55)
	_cannon.add_child(barrel)

	# Four stubby splayed legs.
	for i in 4:
		var ang := PI * 0.25 + float(i) * PI * 0.5
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.16, 0.85, 0.16)
		lm.material = dark
		leg.mesh = lm
		leg.position = Vector3(cos(ang) * 0.6, 0.42, sin(ang) * 0.6)
		leg.rotation = Vector3(0, ang, deg_to_rad(12.0))
		model.add_child(leg)


func _process(_delta: float) -> void:
	# Cannon tracks the target.
	if _cannon and target and is_instance_valid(target):
		track_node_to_target(_cannon, _delta, 60.0, 30.0, 6.0)


func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var origin: Vector3 = muzzle.global_position if muzzle else global_position + Vector3.UP
	var proj := PROJECTILE.instantiate()
	scene.add_child(proj)
	(proj as Node3D).global_position = origin
	var dir := (target.global_position + Vector3.UP * 0.4 - origin).normalized()
	dir = scatter_aim(dir, 2.0)
	if proj.has_method("launch"):
		proj.launch(dir * proj_speed, self, proj_damage, 0.0, 0.0)
	recoil = 1.0
	_muzzle_flash()
