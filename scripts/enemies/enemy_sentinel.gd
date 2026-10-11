class_name EnemySentinel
extends EnemyBase
## Big-fisted bombardier (Quaternius "Robot": a big-headed biped with heavy
## fists, clips Walking/Punch, no gun). Slow and very tanky; it walks to range
## and HURLS everything it fires with its right fist (the Punch clip, released
## at the extension): charged slugs, and every third throw a 3-bomb salvo that
## brackets the player. Get inside its reach and it punches you back out.
## Visuals from a real robot model in sentinel.tscn.

@export var proj_speed: float = 34.0
@export var proj_damage: float = 18.0
## Every few throws it heaves A BOMB SALVO instead: three charges that land
## on and around you, staggered, each under its own warning ring — camping
## one spot near a sentinel is not safe, but the rings give you time to move.
@export var bomb_damage: float = 30.0
@export var bomb_every: int = 3
@export var punch_damage: float = 22.0

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")
const FIST_BONE := "Palm1.R"   ## the hand its Punch clip throws
const THROW_RELEASE := 0.35    ## s into the Punch clip: arm at full extension
const PUNCH_RANGE := 2.8       ## starts a punch when the target is this close
const PUNCH_REACH := 3.2       ## the punch lands if the target is still inside this
const PUNCH_WINDUP := 0.4      ## the clip's draw-back, then the fist arrives
const PUNCH_COOLDOWN := 1.6

var _volley_n: int = 0
var _throw_t: float = 0.0       ## >0: a throw is in the air, released at 0
var _throw_bomb: bool = false
var _punch_t: float = 0.0       ## >0: a punch is winding up
var _punch_cd: float = 0.0


func _ready() -> void:
	max_health = 185.0
	move_speed = 3.4
	turn_speed = 4.0
	sight_range = 42.0
	sight_angle_deg = 180.0
	attack_range = 34.0
	preferred_range = 22.0
	attack_cooldown = 1.9
	telegraph_time = 0.0 # the throw's wind-up (Punch clip) is its tell
	score_value = 180
	stagger_threshold = 120.0
	super._ready()
	# The weapon is the right fist: throws (and the muzzle flash) leave the
	# hand the Punch clip swings.
	muzzle_on_bone(FIST_BONE, Vector3.ZERO, false) # the Punch clip owns the throwing arm


func is_punching() -> bool:
	return _punch_t > 0.0


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state == State.DEAD:
		return
	_punch_cd = maxf(0.0, _punch_cd - delta)
	if _throw_t > 0.0:
		_throw_t -= delta
		if _throw_t <= 0.0:
			_release_throw()


## Inside its reach the fist comes first; a punch in progress owns the body.
func _run_state(delta: float) -> void:
	if _punch_t > 0.0:
		_punch_tick(delta)
		return
	if target and is_instance_valid(target) and _punch_cd <= 0.0 and _throw_t <= 0.0 \
			and (state == State.ATTACK or state == State.CHASE) and not GameState.attack_grace_active() \
			and global_position.distance_to(target.global_position) <= PUNCH_RANGE:
		_punch_t = PUNCH_WINDUP
		if _visual_root and _visual_root.has_method("play_oneshot"):
			_visual_root.play_oneshot("RobotArmature|Robot_Punch", 0.08)
		AudioBus.play_synth_at("servo_step_heavy", global_position, -2.0, 0.8)
		return
	super._run_state(delta)


func _punch_tick(delta: float) -> void:
	_decelerate()
	if target and is_instance_valid(target):
		_face_target(delta)
	_punch_t -= delta
	if _punch_t > 0.0:
		return
	_punch_t = 0.0
	_punch_cd = PUNCH_COOLDOWN
	if target == null or not is_instance_valid(target):
		return
	var to: Vector3 = target.global_position - global_position
	to.y = 0.0
	var fwd := -global_transform.basis.z
	if to.length() > PUNCH_REACH or (to.length() > 0.3 and fwd.dot(to.normalized()) < 0.3):
		return # stepped out of reach or around it: a whiff
	var d := target.get_node_or_null("Damageable")
	if d:
		d.apply_damage(punch_damage, self)
	if target.has_method("shake"):
		target.shake(0.6)
	if "velocity" in target:
		target.velocity += (to.normalized() if to.length() > 0.1 else fwd) * 11.0 + Vector3.UP * 3.0
	AudioBus.play_synth_at("impact_metal", global_position + Vector3.UP, 2.0, 0.6)


## Wind up a throw: the Punch clip starts now (recoil spike), the projectile
## leaves the fist at the arm's full extension, THROW_RELEASE later.
func _perform_attack() -> void:
	if target == null or not is_instance_valid(target) or _throw_t > 0.0:
		return
	_volley_n += 1
	_throw_bomb = _volley_n % bomb_every == 0
	_throw_t = THROW_RELEASE
	recoil = 1.0


func _release_throw() -> void:
	if target == null or not is_instance_valid(target) or state == State.DEAD:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var origin: Vector3 = muzzle.global_position if muzzle else global_position + Vector3.UP
	_muzzle_flash()
	if _throw_bomb:
		_bomb_salvo(scene, origin)
		return
	var proj := PROJECTILE.instantiate()
	scene.add_child(proj)
	(proj as Node3D).global_position = origin
	var dir := (target.global_position + Vector3.UP * 0.4 - origin).normalized()
	dir = scatter_aim(dir, 2.0)
	if proj.has_method("launch"):
		proj.launch(dir * proj_speed, self, proj_damage, 0.0, 0.0)
	AudioBus.play_synth_at("grenade_throw", origin, -4.0, 0.85)

## BOMB SALVO: one heave, three charges bracketing the player: one on them,
## two scattered around, landing staggered (longer flights for the outer
## two). Each impact point burns its warning ring for exactly its flight, so
## the answer is to MOVE and keep moving. After the salvo it re-rolls its
## approach angle: it resets its throwing lane instead of standing forever.
func _bomb_salvo(scene: Node, origin: Vector3) -> void:
	AudioBus.play_synth_at("grenade_throw", origin, -2.0, 0.6)
	var center: Vector3 = target.global_position
	for i in 3:
		var pt := center
		if i > 0:
			var ang := randf() * TAU
			pt += Vector3(cos(ang), 0.0, sin(ang)) * randf_range(2.2, 4.5)
		var flight := 0.9 + 0.35 * float(i)
		spawn_ground_warning(pt, 2.4, flight)
		EnemyBomb.lob_at(scene, origin, pt, flight, bomb_damage * 0.75)
	_approach_angle = randf() * TAU # displace: reset the throwing lane
