class_name EnemyOverseer
extends EnemyBase
## A hovering gunship boss. It floats above the arena, tracks the player, and
## rakes them with escalating projectile volleys; wounded, it fires faster and
## starts vomiting kamikaze Seekers. Three phases keyed to health. Uses the HUD
## boss bar. Built entirely in code (no rig scene).

@export var fly_height: float = 6.5
@export var proj_speed: float = 40.0
@export var proj_damage: float = 13.0

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")
const SEEKER := preload("res://scenes/enemies/seeker.tscn")
const MUZZLES := [
	Vector3(1.3, -0.1, 0.6), Vector3(-1.3, -0.1, 0.6),
	Vector3(0.7, -0.2, 1.1), Vector3(-0.7, -0.2, 1.1),
]

var _ring: MeshInstance3D
var _eye_mat: StandardMaterial3D
var _eye_light: OmniLight3D
var _summon_cd: float = 0.0
var _spin: float = 0.0

func _ready() -> void:
	_build_model()
	super._ready()
	max_health = 1500.0
	stagger_threshold = 100000.0
	move_speed = 4.0
	turn_speed = 2.4
	sight_range = 90.0
	sight_angle_deg = 320.0
	attack_range = 64.0
	preferred_range = 30.0
	attack_cooldown = 1.7
	score_value = 2500
	head_radius = 1.0
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 4.0
	flinch_knockback = 0.0
	_do_entrance.call_deferred()

func _build_model() -> void:
	var model := Node3D.new()
	model.name = "Model"
	add_child(model)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.09, 0.1, 0.13)
	dark.metallic = 0.7
	dark.roughness = 0.4
	# Main disc hull.
	var hull := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 1.0
	hm.bottom_radius = 1.7
	hm.height = 0.9
	hm.radial_segments = 10
	hull.mesh = hm
	hull.material_override = dark
	hull.position = Vector3(0, fly_height, 0)
	model.add_child(hull)
	# Upper dome.
	var dome := MeshInstance3D.new()
	var dsm := SphereMesh.new()
	dsm.radius = 0.9
	dsm.height = 1.1
	dome.mesh = dsm
	dome.material_override = dark
	dome.position = Vector3(0, fly_height + 0.5, 0)
	model.add_child(dome)
	# Rotating menace ring.
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.8
	tm.outer_radius = 2.1
	_ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.emission_enabled = true
	rmat.albedo_color = Color(1.0, 0.3, 0.18)
	rmat.emission = Color(1.0, 0.32, 0.18)
	rmat.emission_energy_multiplier = 2.5
	_ring.material_override = rmat
	_ring.position = Vector3(0, fly_height - 0.1, 0)
	model.add_child(_ring)
	# Big central eye.
	var eyem := MeshInstance3D.new()
	var esm := SphereMesh.new()
	esm.radius = 0.5
	esm.height = 1.0
	eyem.mesh = esm
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.emission_enabled = true
	_eye_mat.albedo_color = Color(1.0, 0.25, 0.12)
	_eye_mat.emission = Color(1.0, 0.3, 0.15)
	_eye_mat.emission_energy_multiplier = 5.0
	eyem.material_override = _eye_mat
	eyem.position = Vector3(0, fly_height, 0.7)
	model.add_child(eyem)

	var eye_node := Node3D.new()
	eye_node.name = "Eye"
	eye_node.position = Vector3(0, fly_height, 0.9)
	add_child(eye_node)
	eye = eye_node
	var mz := Node3D.new()
	mz.name = "Muzzle"
	mz.position = Vector3(0, fly_height - 0.1, 1.0)
	add_child(mz)
	muzzle = mz

	_eye_light = OmniLight3D.new()
	_eye_light.light_color = Color(1.0, 0.3, 0.15)
	_eye_light.light_energy = 4.0
	_eye_light.omni_range = 9.0
	_eye_light.position = Vector3(0, fly_height, 0.6)
	add_child(_eye_light)

func _do_entrance() -> void:
	GameState.announce_boss(self)
	AudioBus.play_synth_ui("eas_alert", -6.0)
	AudioBus.play_synth_at("explosion", global_position, 5.0, 0.5)
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(1.2)

func _phase() -> int:
	if hp == null or hp.max_health <= 0.0:
		return 1
	var frac := hp.current_health / hp.max_health
	if frac <= 0.33:
		return 3
	elif frac <= 0.66:
		return 2
	return 1

func _apply_gravity(_delta: float) -> void:
	pass

func _move_toward(dest: Vector3, delta: float) -> void:
	var ty: float = (target.global_position.y if target else 0.0) + fly_height
	var to := Vector3(dest.x, ty, dest.z) - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() > 0.05:
		var d := flat.normalized()
		velocity.x = move_toward(velocity.x, d.x * move_speed, 8.0 * delta)
		velocity.z = move_toward(velocity.z, d.z * move_speed, 8.0 * delta)
	velocity.y = move_toward(velocity.y, (ty - global_position.y) * 4.0, 20.0 * delta)

func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	_spin += delta
	if _ring:
		_ring.rotation.y = _spin * 1.2
	if _eye_mat:
		var ph := _phase()
		_eye_mat.emission_energy_multiplier = 4.0 + ph * 1.5 + recoil * 6.0
	if _summon_cd > 0.0:
		_summon_cd -= delta

## A spreading volley from several muzzles; heavier with each phase, and in the
## final phase it also spits out a Seeker.
func _perform_attack() -> void:
	if target == null:
		return
	recoil = 1.0
	var scene := get_tree().current_scene
	if scene == null:
		return
	var phase := _phase()
	var shots := 2 + phase # 3 / 4 / 5 bolts
	for i in shots:
		var off: Vector3 = MUZZLES[i % MUZZLES.size()]
		var origin: Vector3 = global_transform * Vector3(off.x, off.y + fly_height, off.z)
		var proj := PROJECTILE.instantiate()
		scene.add_child(proj)
		(proj as Node3D).global_position = origin
		var dir := (target.global_position + Vector3.UP * 0.6 - origin).normalized()
		dir = scatter_aim(dir, 3.0 + float(i) * 1.2)
		if proj.has_method("launch"):
			proj.launch(dir * proj_speed, self, proj_damage, 0.0, 0.0)
	_muzzle_flash()
	AudioBus.play_synth_at("drone_shot", global_position, -2.0, 0.8)
	if phase >= 3:
		_maybe_summon(scene)

func _maybe_summon(scene: Node) -> void:
	if _summon_cd > 0.0:
		return
	_summon_cd = 7.0
	var s := SEEKER.instantiate()
	scene.add_child(s)
	(s as Node3D).global_position = global_position + Vector3(randf_range(-3, 3), fly_height - 1.5, randf_range(-3, 3))
	AudioBus.play_synth_at("broadcast_blip", global_position, -2.0, 0.7)

func _on_died(source: Node) -> void:
	set_state(State.DEAD)
	GameState.add_kill(score_value, _kill_label())
	GameState.hit_stop(0.35, 0.5)
	set_physics_process(false)
	var scene := get_tree().current_scene
	if scene:
		for i in 6:
			var fx := EXPLOSION.instantiate()
			scene.add_child(fx)
			(fx as Node3D).global_position = global_position + Vector3(randf_range(-2, 2), fly_height + randf_range(-1, 2), randf_range(-2, 2))
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(1.5)
	queue_free()
