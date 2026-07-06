class_name EnemyRoller
extends EnemyDog
## ROLLER — a monowheel brawler: a gold drum balanced on a single fat wheel, with
## whipping spring-arms. It rolls in fast and rams, knocking you back. Tougher than
## the K-9 hound but a touch slower to turn, so circle-strafe it.
##
## Signature move: the RAM. A monowheel leaping into the air like the hound would
## look wrong, so this fully replaces EnemyDog's airborne pounce with a grounded
## charge: a brief plant/spin-up tell, then a fast straight-line drive at the
## player that ends on impact (not on landing — it never leaves the floor) with
## a bite plus a shove that knocks the player back.

const RAM_SPEED := 18.0        ## faster than move_speed — this is the charge, not the chase
const RAM_WINDUP := 0.35       ## plant/spin-up tell before it commits
const RAM_MAX_TIME := 0.55     ## charge times out even if it never lands a hit
const RAM_IMPACT_RANGE := 2.4  ## charge ends early once it's this close
const RAM_KNOCK := 11.0        ## horizontal shove applied to the player on impact

var _ramming: bool = false
var _ram_t: float = 0.0
var _ram_windup_t: float = 0.0
var _ram_cd: float = 0.0

func _ready() -> void:
	super._ready()
	bite_damage = 24.0
	max_health = 175.0    # a heavy steel drum — soaks more than a hound
	move_speed = 8.0
	turn_speed = 7.5
	attack_range = 3.4
	score_value = 175
	stagger_threshold = 46.0
	hp.max_health = max_health
	hp.current_health = max_health

## Plant → charge → impact, all on the ground. This can't fall through to
## EnemyDog's _physics_process (that's the airborne pounce we're replacing), so
## the base ground-AI tick it would otherwise reach via `super` is replicated
## here instead.
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if _emp_t > 0.0:
		_emp_t = maxf(0.0, _emp_t - delta)
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		_apply_gravity(delta)
		move_and_slide()
		return
	_ram_cd = maxf(0.0, _ram_cd - delta)
	if _ramming:
		# Gravity holds it down — no launch, no hop, just a fast roll.
		_apply_gravity(delta)
		move_and_slide()
		_ram_t += delta
		var close := target != null and is_instance_valid(target) \
			and global_position.distance_to(target.global_position) <= RAM_IMPACT_RANGE
		if close or _ram_t > RAM_MAX_TIME:
			_ramming = false
			_ram_cd = pounce_cooldown
			_ram_impact()
		return
	if _ram_windup_t > 0.0:
		_ram_windup_t -= delta
		_decelerate()
		_face_target(delta)
		_apply_gravity(delta)
		move_and_slide()
		if _ram_windup_t <= 0.0:
			_launch_ram()
		return
	# Base ground AI (replicated from EnemyBase._physics_process — see comment above).
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_state_timer += delta
	recoil = move_toward(recoil, 0.0, delta * 9.0)
	_perceive()
	_run_state(delta)
	_apply_gravity(delta)
	move_and_slide()
	_update_hit_react(delta)
	_update_overload(delta)
	_oil_cd = maxf(0.0, _oil_cd - delta)
	_poise = maxf(0.0, _poise - delta * 26.0)
	_update_locomotion_audio(delta)
	if target and _ram_cd <= 0.0 and is_on_floor() \
			and state in [State.CHASE, State.ATTACK]:
		var dist := global_position.distance_to(target.global_position)
		# Reuse the hound's pounce band — same "mid range, has to commit" fairness.
		if dist >= pounce_min and dist <= pounce_max and _can_see(target):
			_ram_windup_t = RAM_WINDUP
			recoil = 0.6
			AudioBus.play_synth_at("overlord_glitch", global_position, -8.0, 1.9)

func _launch_ram() -> void:
	if target == null or not is_instance_valid(target):
		return
	_ramming = true
	_ram_t = 0.0
	var dir := target.global_position - global_position
	dir.y = 0.0
	dir = dir.normalized()
	velocity.x = dir.x * RAM_SPEED
	velocity.z = dir.z * RAM_SPEED
	recoil = 1.0
	AudioBus.play_synth_at("impact_metal", global_position, -7.0, 2.2)

## Bite + shove on landing a ram — the knockback is what sells "rammed", not just bitten.
func _ram_impact() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and player is Node3D \
			and global_position.distance_to((player as Node3D).global_position) <= RAM_IMPACT_RANGE + 0.2:
		var d = player.get_node_or_null("Damageable")
		if d:
			d.apply_damage(bite_damage, self)
		var away: Vector3 = (player as Node3D).global_position - global_position
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
		if player is CharacterBody3D and "velocity" in player:
			(player as CharacterBody3D).velocity += away * RAM_KNOCK + Vector3.UP * 2.5
	AudioBus.play_synth_at("impact_metal", global_position, -5.0, 1.6)
