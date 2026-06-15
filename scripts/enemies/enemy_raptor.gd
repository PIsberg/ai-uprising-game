class_name EnemyRaptor
extends EnemyBase
## RAPTOR — a flying heavy gunner (Quaternius "Robot Enemy Flying Gun"). It hovers
## at mid-range, strafes to stay a hard target, and rakes the player with bolt
## bursts. Tougher and higher-flying than the recon drone — shoot it out of the
## air. RobotModel on $Model drives its clips; killed, it tumbles and bursts.

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")

@export var hover_height: float = 4.2
@export var strafe_speed: float = 4.2
@export var proj_speed: float = 40.0
@export var proj_damage: float = 9.0
@export var burst_count: int = 4
@export var burst_interval: float = 0.12

var _hover: float = 0.0
var _strafe_dir: float = 1.0
var _strafe_t: float = 0.0
var _burst_left: int = 0
var _burst_t: float = 0.0
var _dying: bool = false
var _fall_time: float = 0.0

@onready var _eye_light: OmniLight3D = $EyeLight

func _ready() -> void:
	super._ready()
	max_health = 95.0
	move_speed = 7.0
	turn_speed = 8.0
	sight_range = 48.0
	sight_angle_deg = 300.0
	attack_range = 36.0
	preferred_range = 18.0
	attack_cooldown = 1.9
	score_value = 185
	head_radius = 0.6
	flinch_knockback = 1.0
	hp.max_health = max_health
	hp.current_health = max_health
	_hover = randf() * TAU
	_strafe_dir = 1.0 if randf() < 0.5 else -1.0

func _apply_gravity(_delta: float) -> void:
	pass # it flies (until it dies)

func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	if _eye_light:
		_eye_light.light_energy = 1.2 + recoil * 2.2 + (1.5 if is_enraged() else 0.0)

func _state_chase(delta: float) -> void:
	if target == null:
		set_state(State.IDLE)
		return
	if _can_see(target) and global_position.distance_to(target.global_position) <= attack_range:
		set_state(State.ATTACK)
		return
	_fly_to(target.global_position, delta)

func _state_attack(delta: float) -> void:
	if target == null or not _can_see(target):
		set_state(State.CHASE)
		return
	_face_target(delta)
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(1.2, 2.6)
		_strafe_dir = -_strafe_dir
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var dirn := to.normalized() if to.length() > 0.01 else -global_transform.basis.z
	var fwd := 0.0
	if dist > preferred_range * 1.15:
		fwd = 1.0
	elif dist < preferred_range * 0.85:
		fwd = -1.0
	var right := dirn.cross(Vector3.UP)
	var mv := right * _strafe_dir * strafe_speed + dirn * fwd * move_speed * 0.8
	velocity.x = move_toward(velocity.x, mv.x, 14.0 * delta)
	velocity.z = move_toward(velocity.z, mv.z, 14.0 * delta)
	_hover += delta * 2.0
	var ty: float = target.global_position.y + hover_height + sin(_hover) * 0.3
	velocity.y = move_toward(velocity.y, (ty - global_position.y) * 4.0, 30.0 * delta)
	if _attack_timer <= 0.0 and _burst_left <= 0:
		_burst_left = burst_count
		_burst_t = 0.0
		_attack_timer = attack_interval()

func _fly_to(dest: Vector3, delta: float) -> void:
	var ty: float = (target.global_position.y if target else dest.y) + hover_height
	var to := Vector3(dest.x, ty, dest.z) - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() > 0.05:
		var d := flat.normalized()
		var spd := chase_speed()
		velocity.x = move_toward(velocity.x, d.x * spd, 14.0 * delta)
		velocity.z = move_toward(velocity.z, d.z * spd, 14.0 * delta)
		_face_dir(d, delta)
	velocity.y = move_toward(velocity.y, (ty - global_position.y) * 4.0, 30.0 * delta)

func _physics_process(delta: float) -> void:
	if _dying:
		_fall_dead(delta)
		return
	super._physics_process(delta)
	if _burst_left > 0:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_fire_one()
			_burst_left -= 1
			_burst_t = burst_interval

func _fire_one() -> void:
	if target == null or not is_instance_valid(target) or muzzle == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var proj := PROJECTILE.instantiate()
	scene.add_child(proj)
	(proj as Node3D).global_position = muzzle.global_position
	var dir := (target.global_position + Vector3.UP * 0.5 - muzzle.global_position).normalized()
	dir = scatter_aim(dir, 3.0)
	if proj.has_method("launch"):
		proj.launch(dir * proj_speed, self, proj_damage, 0.0, 0.0)
	recoil = 1.0
	_muzzle_flash()
	AudioBus.play_synth_at("drone_shot", muzzle.global_position, -4.0, randf_range(0.95, 1.08))

## Killed: lose lift, tumble down, and burst on impact.
func _on_died(_source: Node) -> void:
	if _dying:
		return
	_dying = true
	set_state(State.DEAD)
	GameState.add_kill(score_value, _kill_label())
	collision_layer = 0
	collision_mask = 1
	velocity += Vector3(randf_range(-2, 2), 1.5, randf_range(-2, 2))
	if _damaged_emitter == null or not is_instance_valid(_damaged_emitter):
		_damaged_emitter = DAMAGED_FX.instantiate()
		add_child(_damaged_emitter)

func _fall_dead(delta: float) -> void:
	velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	velocity.x = move_toward(velocity.x, 0.0, 4.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 4.0 * delta)
	rotation.x += delta * 4.0
	rotation.z += delta * 5.5
	move_and_slide()
	_fall_time += delta
	if is_on_floor() or _fall_time > 4.0:
		var fx := EXPLOSION.instantiate()
		get_parent().add_child(fx)
		(fx as Node3D).global_position = global_position
		AudioBus.play_synth_at("explosion", global_position, 0.0, 1.1)
		queue_free()
