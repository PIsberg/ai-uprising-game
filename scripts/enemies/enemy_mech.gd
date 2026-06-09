class_name EnemyMech
extends EnemyBase

@export var projectile_scene: PackedScene
@export var projectile_speed: float = 30.0
@export var rocket_damage: float = 40.0
@export var rocket_splash_radius: float = 4.5
@export var rocket_splash_damage: float = 35.0
@export var charge_threshold: float = 6.0
@export var charge_speed: float = 9.5
@export var stomp_damage: float = 25.0

var _charging: bool = false

# AnimationTree: locomotion blendspace (idle<->walk) + attack OneShot layered on
# top, so the mech fires its launcher arm while its legs keep striding.
@onready var _anim_tree: AnimationTree = $AnimationTree
var _glow_time: float = 0.0
var _glow_mat: StandardMaterial3D
var _slam_windup: float = 0.0 ## >0 while telegraphing a ground-slam before it lands.


func _ready() -> void:
	super._ready()
	max_health = 350.0
	move_speed = 3.1
	turn_speed = 3.6
	sight_range = 30.0
	attack_range = 24.0
	preferred_range = 13.0
	attack_cooldown = 2.2
	score_value = 250
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 4.0
	flinch_knockback = 1.2 # Heavy chassis barely budges when shot.

	_glow_mat = preload("res://assets/materials/glow_red.tres").duplicate() as StandardMaterial3D
	get_node("Rig/Hips/Spine/Reactor").material_override = _glow_mat
	get_node("Rig/Hips/Spine/Eye/EyeMesh").material_override = _glow_mat


func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	# Tick a telegraphed ground-slam; it lands when the windup elapses.
	if _slam_windup > 0.0:
		_slam_windup -= delta
		if _slam_windup <= 0.0:
			_stomp_shockwave()
	# Reactor glow pulses slowly, flaring on weapon recoil + during a slam windup.
	_glow_time += delta
	if _glow_mat:
		var wind := 8.0 if _slam_windup > 0.0 else 0.0
		_glow_mat.emission_energy_multiplier = 5.0 + sin(_glow_time * (2.5 + damage_heat * 6.0)) * 1.5 + recoil * 8.0 + damage_heat * 8.0 + (5.0 if is_enraged() else 0.0) + wind
	# Slow, weighty stride blended by ground speed.
	var speed := Vector2(velocity.x, velocity.z).length()
	_anim_tree.set("parameters/Locomotion/blend_position",
		clampf(speed / move_speed, 0.0, 1.0))


func _state_attack(delta: float) -> void:
	if target == null or not _can_see(target):
		set_state(State.CHASE)
		return
	_face_target(delta)
	var dist := global_position.distance_to(target.global_position)
	if dist < charge_threshold:
		_do_stomp_if_close()
		_charging = true
	else:
		_charging = false
	if _charging:
		var dir := (target.global_position - global_position)
		dir.y = 0
		dir = dir.normalized()
		velocity.x = move_toward(velocity.x, dir.x * charge_speed, 16.0 * delta)
		velocity.z = move_toward(velocity.z, dir.z * charge_speed, 16.0 * delta)
	else:
		_decelerate()
		if _attack_timer <= 0.0:
			_fire_rocket()
			_attack_timer = attack_interval()

func _do_stomp_if_close() -> void:
	if _attack_timer > 0.0 or _slam_windup > 0.0:
		return
	if target == null or global_position.distance_to(target.global_position) >= 3.5:
		return
	_attack_timer = 1.8
	# Telegraph: a growing warning ring + flaring reactor, THEN the slam lands —
	# giving the player a window to dash clear.
	_slam_windup = 0.55
	_spawn_slam_telegraph(0.55, 4.5)
	AudioBus.play_synth_at("mech_step", global_position, 2.0, 0.7)

func _spawn_slam_telegraph(dur: float, radius: float) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.3
	tm.outer_radius = radius
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.2, 0.1, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.1)
	mat.emission_energy_multiplier = 4.0
	ring.material_override = mat
	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position + Vector3(0, 0.08, 0)
	# Pulse opacity up to full as the slam approaches, then it's freed.
	var tw := ring.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.85, dur)
	tw.tween_callback(ring.queue_free)

## Ground-slam: AoE damage + knockback within radius, a hard camera shake, and
## an expanding shockwave ring so the slam reads and hits with weight.
func _stomp_shockwave() -> void:
	const RADIUS := 4.5
	recoil = 1.0
	AudioBus.play_synth_at("mech_step", global_position, 5.0, 0.45)
	AudioBus.play_synth_at("explosion", global_position, 0.0, 1.4)
	var p := get_tree().get_first_node_in_group("player")
	if p is CharacterBody3D and (p as Node3D).global_position.distance_to(global_position) <= RADIUS:
		var d := p.get_node_or_null("Damageable")
		if d:
			d.apply_damage(stomp_damage, self)
		if p.has_method("shake"):
			p.shake(0.95)
		var away: Vector3 = (p as Node3D).global_position - global_position
		away.y = 0.0
		if away.length() > 0.1:
			p.velocity += away.normalized() * 13.0 + Vector3.UP * 4.5
	_spawn_shockwave_ring(RADIUS)

func _spawn_shockwave_ring(radius: float) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.25
	tm.outer_radius = 0.6
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.5, 0.2, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.15)
	mat.emission_energy_multiplier = 6.0
	ring.material_override = mat
	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position + Vector3(0, 0.15, 0)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius * 1.6, 1.0, radius * 1.6), 0.4)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tw.chain().tween_callback(ring.queue_free)

func _fire_rocket() -> void:
	if target == null or muzzle == null or projectile_scene == null:
		return
	recoil = 1.0
	_anim_tree.set("parameters/OneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_muzzle_flash()
	var proj := projectile_scene.instantiate()
	get_tree().current_scene.add_child(proj)
	proj.global_position = muzzle.global_position
	var dir := (target.global_position + Vector3.UP * 0.6 - muzzle.global_position).normalized()
	dir = scatter_aim(dir) # difficulty-driven inaccuracy
	if proj.has_method("launch"):
		proj.launch(dir * projectile_speed, self, rocket_damage, rocket_splash_radius, rocket_splash_damage)
	AudioBus.play_synth_at("plasma_fire", muzzle.global_position, 1.0, randf_range(0.72, 0.82))
