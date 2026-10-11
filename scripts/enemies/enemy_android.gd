class_name EnemyAndroid
extends EnemyBase

@export var hitscan_damage: float = 9.0
@export var burst_count: int = 5
@export var burst_interval: float = 0.08
@export var burst_spread_deg: float = 2.0
@export var tracer_scene: PackedScene
@export var muzzle_flash_scene: PackedScene
@export var cover_search_radius: float = 12.0
@export var flank_chance: float = 0.55
## The ANDROID's own model (android.tscn, Quaternius "Leela": armless, one
## round lens on its face pod, digitigrade claw legs). All off by default:
## every subclass scene carries an armed humanoid of its own.
@export var lens_bone: String = ""              ## fire from this bone's lens
@export var lens_offset: Vector3 = Vector3.ZERO ## the lens, off the bone's pivot (m)
@export var kick_damage: float = 0.0            ## >0: up close it kicks (Kick clip)
@export var hop_jukes: bool = false             ## its jukes are side-hops

const KICK_RANGE := 2.4     ## starts a kick when the target is this close
const KICK_REACH := 2.9     ## the kick lands if the target is still inside this
const KICK_WINDUP := 0.32   ## the Kick clip's leg lift, then the claw arrives
const KICK_COOLDOWN := 1.5
const HOP_SPEED := 5.0      ## juke take-off (gravity 24: ~0.42 s up, ~0.5 m)

var _burst_remaining: int = 0
var _burst_timer: float = 0.0
var _seeking_cover: bool = false
var _cover_pos: Vector3
var _last_flank_check: float = 0.0
var _dodge_cd: float = 2.0  ## Time until the next evasive sidestep.
var _dodge_dir: float = 1.0
var _dodge_time: float = 0.0 ## >0 while mid-juke.
var _hop_air: bool = false  ## a hop juke has left the floor and not landed
var _kick_t: float = 0.0    ## >0: a kick is winding up
var _kick_cd: float = 0.0

# Visuals/animation come from the imported model on $Model (RobotModel drives
# idle/run blending and fires the Shoot clip off the recoil spike).

func _ready() -> void:
	super._ready()
	max_health = 110.0
	move_speed = 5.8
	turn_speed = 8.5
	sight_range = 34.0
	attack_range = 26.0
	preferred_range = 12.0
	attack_cooldown = 1.6
	score_value = 150
	hp.max_health = max_health
	hp.current_health = max_health
	if lens_bone != "":
		muzzle_on_bone(lens_bone, lens_offset)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_kick_cd = maxf(0.0, _kick_cd - delta)
	if _burst_remaining > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_fire_one_shot()
			_burst_remaining -= 1
			_burst_timer = burst_interval

## Evasive juke timer: periodically begins a ~0.32s sidestep. Returns true while
## mid-juke so _state_attack drives the lateral burst.
func _tick_dodge(delta: float) -> bool:
	_dodge_cd -= delta
	if _dodge_time <= 0.0 and _dodge_cd <= 0.0 and not _seeking_cover:
		_dodge_time = 0.32
		_dodge_dir = 1.0 if randf() > 0.5 else -1.0
		_dodge_cd = randf_range(1.6, 3.2)
		if hop_jukes and is_on_floor():
			velocity.y = HOP_SPEED
			_hop_air = true
			if _visual_root and _visual_root.has_method("play_oneshot_over"):
				_visual_root.play_oneshot_over("Jump", 2.0 * HOP_SPEED / float(ProjectSettings.get_setting("physics/3d/default_gravity")), 0.06)
	if _dodge_time > 0.0:
		_dodge_time -= delta
		return true
	if _hop_air and is_on_floor() and velocity.y <= 0.0:
		_hop_air = false
	return _hop_air # still airborne: ride the hop out sideways

## Inside its reach the claw foot comes first; a kick in progress owns the body.
func _run_state(delta: float) -> void:
	if _kick_t > 0.0:
		_kick_tick(delta)
		return
	if kick_damage > 0.0 and _kick_cd <= 0.0 and _burst_remaining <= 0 and is_on_floor() \
			and target and is_instance_valid(target) and (state == State.ATTACK or state == State.CHASE) \
			and not GameState.attack_grace_active() \
			and global_position.distance_to(target.global_position) <= KICK_RANGE:
		_kick_t = KICK_WINDUP
		if _visual_root and _visual_root.has_method("play_oneshot"):
			_visual_root.play_oneshot("Kick", 0.08)
		AudioBus.play_synth_at("servo_step_heavy", global_position, -4.0, 1.25)
		return
	super._run_state(delta)

func _kick_tick(delta: float) -> void:
	_decelerate()
	if target and is_instance_valid(target):
		_face_target(delta)
	_kick_t -= delta
	if _kick_t > 0.0:
		return
	_kick_t = 0.0
	_kick_cd = KICK_COOLDOWN
	if target == null or not is_instance_valid(target):
		return
	var to: Vector3 = target.global_position - global_position
	to.y = 0.0
	var fwd := -global_transform.basis.z
	if to.length() > KICK_REACH or (to.length() > 0.3 and fwd.dot(to.normalized()) < 0.3):
		return # stepped out of reach or around it: a whiff
	var d := target.get_node_or_null("Damageable")
	if d:
		d.apply_damage(kick_damage, self)
	if target.has_method("shake"):
		target.shake(0.45)
	if "velocity" in target:
		target.velocity += (to.normalized() if to.length() > 0.1 else fwd) * 9.0 + Vector3.UP * 2.5
	AudioBus.play_synth_at("impact_metal", global_position + Vector3.UP * 0.6, 0.0, 0.9)

func _state_attack(delta: float) -> void:
	if target == null or not _can_see(target):
		set_state(State.CHASE)
		return
	_face_target(delta)
	# Periodically flank
	_last_flank_check += delta
	if _last_flank_check > 3.0:
		_last_flank_check = 0.0
		if randf() < flank_chance:
			_seeking_cover = true
			_cover_pos = _pick_flank_position()
	var dodging := _tick_dodge(delta)
	if _seeking_cover and global_position.distance_to(_cover_pos) > 1.2:
		_move_toward(_cover_pos, delta)
	elif dodging:
		_dodge_time -= delta
		var to := target.global_position - global_position
		to.y = 0.0
		var side := to.normalized().cross(Vector3.UP) * _dodge_dir
		velocity.x = move_toward(velocity.x, side.x * 9.0, 45.0 * delta)
		velocity.z = move_toward(velocity.z, side.z * 9.0, 45.0 * delta)
		if _attack_timer <= 0.0 and not GameState.attack_grace_active():
			_start_burst()
			_attack_timer = attack_interval()
	else:
		_seeking_cover = false
		_decelerate()
		if _attack_timer <= 0.0 and not GameState.attack_grace_active():
			_start_burst()
			_attack_timer = attack_interval()

func _pick_flank_position() -> Vector3:
	if target == null:
		return global_position
	# Pick a point perpendicular to player->self vector at preferred range
	var from_target := global_position - target.global_position
	from_target.y = 0
	var side := from_target.normalized().cross(Vector3.UP) * (1.0 if randf() > 0.5 else -1.0)
	return target.global_position + (from_target.normalized() + side).normalized() * preferred_range

func _start_burst() -> void:
	_burst_remaining = burst_count
	_burst_timer = 0.0
	_bark_attack() # once per burst, not per shot

func _fire_one_shot() -> void:
	if target == null or muzzle == null:
		return
	recoil = 1.0
	if muzzle_flash_scene:
		var m := muzzle_flash_scene.instantiate()
		muzzle.add_child(m)
	AudioBus.play_synth_at("drone_shot", muzzle.global_position, -3.0, randf_range(1.05, 1.15))
	var origin := muzzle.global_position
	var target_pos := target.global_position + Vector3.UP * 0.6
	var dir := (target_pos - origin).normalized()
	# Inherent burst scatter + difficulty-driven inaccuracy.
	dir = scatter_aim(dir, burst_spread_deg)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 80.0)
	q.collision_mask = 0b0000011 # world + player
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var end_point := origin + dir * 80.0
	if not hit.is_empty():
		end_point = hit.position
		var col: Node = hit.collider
		var d: Node = col.get_node_or_null("Damageable") if col else null
		if d:
			d.apply_damage(hitscan_damage, self)
	if tracer_scene:
		var t := tracer_scene.instantiate()
		get_tree().current_scene.add_child(t)
		if t.has_method("setup"):
			t.setup(origin, end_point)

func _perform_attack() -> void:
	_start_burst()
