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

var _burst_remaining: int = 0
var _burst_timer: float = 0.0
var _seeking_cover: bool = false
var _cover_pos: Vector3
var _last_flank_check: float = 0.0
var _dodge_cd: float = 2.0  ## Time until the next evasive sidestep.
var _dodge_dir: float = 1.0
var _dodge_time: float = 0.0 ## >0 while mid-juke.

# Skeletal animation via AnimationTree: a locomotion blendspace (idle<->walk by
# speed) with the attack as a OneShot layered on top, so the android fires its
# upper body WHILE the legs keep walking (the attack clip only keys arms+spine).
@onready var _anim_tree: AnimationTree = $AnimationTree
@onready var _neck: Node3D = $Rig/Hips/Spine/Neck
var _glow_time: float = 0.0
var _glow_mat: StandardMaterial3D


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
	_glow_mat = preload("res://assets/materials/glow_red.tres").duplicate() as StandardMaterial3D
	get_node("Rig/Hips/Spine/ChestCore").material_override = _glow_mat
	get_node("Rig/Hips/Spine/Neck/EyeL").material_override = _glow_mat
	get_node("Rig/Hips/Spine/Neck/EyeR").material_override = _glow_mat


func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	# Eye/core glow pulses gently, flaring on weapon recoil.
	_glow_time += delta
	if _glow_mat:
		var enrage := 4.0 if is_enraged() else 0.0
		_glow_mat.emission_energy_multiplier = 4.0 + sin(_glow_time * (3.0 + damage_heat * 6.0)) * 1.0 + recoil * 6.0 + damage_heat * 7.0 + enrage
	# Head tracks the player (no clip keys the neck, so this layers cleanly).
	track_node_to_target(_neck, delta, 60.0, 30.0, 8.0)
	# Blend idle<->walk by ground speed; the AnimationTree handles the rest.
	var speed := Vector2(velocity.x, velocity.z).length()
	_anim_tree.set("parameters/Locomotion/blend_position",
		clampf(speed / move_speed, 0.0, 1.0))


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
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
	if _dodge_time > 0.0:
		_dodge_time -= delta
		return true
	return false

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
		if _attack_timer <= 0.0:
			_start_burst()
			_attack_timer = attack_interval()
	else:
		_seeking_cover = false
		_decelerate()
		if _attack_timer <= 0.0:
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

func _fire_one_shot() -> void:
	if target == null or muzzle == null:
		return
	recoil = 1.0
	# Fire the upper-body attack OneShot; legs keep walking.
	_anim_tree.set("parameters/OneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
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
