class_name EnemyHunter
extends EnemyBase
## Sleek, fast skirmisher with shoulder cannons. Circle-strafes at mid range and
## fires rapid bolt bursts. Visuals from a real robot model in hunter.tscn.

@export var proj_speed: float = 46.0
@export var proj_damage: float = 7.0
@export var burst_count: int = 3

## BLADE DASH: the chassis (quaternius_gunner_bladed) carries prominent arm
## blades that never did anything — this was a pure ranged strafer. On a
## cooldown, from mid range, it commits: a fast gap-closing dash that rakes
## the blades on arrival, then kicks back out to strafing bolt bursts. Rides
## the base lunge machinery, stretched into a real dash.
@export var dash_cooldown: float = 6.5
@export var rake_damage: float = 16.0

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")

var _burst_left: int = 0
var _burst_t: float = 0.0
var _dash_cd: float = 0.0
var _raked: bool = false


func _ready() -> void:
	max_health = 88.0   # heavier than a hound to match the bulky armoured tick-body it wears (still a fragile, kill-it-fast skirmisher)
	move_speed = 7.6
	turn_speed = 8.0
	sight_range = 38.0
	sight_angle_deg = 200.0
	attack_range = 26.0
	preferred_range = 16.0
	attack_cooldown = 1.6
	score_value = 120
	stagger_threshold = 45.0
	combat_strafe = true # circle-strafe skirmisher: stays mobile + banks into it (was a static plinker, unlike the stationary android)
	_dash_cd = randf_range(2.0, 5.0) # stagger a pack's first dashes
	super._ready()


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
	# Blade dash: commit from mid range, in combat, off cooldown.
	_dash_cd -= delta
	if _dash_cd <= 0.0 and state == State.ATTACK and _lunge_time <= 0.0 \
			and target and is_instance_valid(target):
		var gap := global_position.distance_to(target.global_position)
		if gap > 6.0 and gap < 18.0:
			_dash_cd = dash_cooldown
			_raked = false
			attack_lunge_speed = 20.0
			_attack_lunge()
			_lunge_time = 0.55 # stretch the base pounce into a truer dash
			AudioBus.play_synth_at("grenade_throw", global_position, -6.0, 1.35)
	# The rake lands once per dash, the moment the blades reach the target.
	if _lunge_time > 0.0 and not _raked and target and is_instance_valid(target) \
			and global_position.distance_to(target.global_position) < 2.7:
		_raked = true
		var d = (target as Node).get_node_or_null("Damageable")
		if d and d.has_method("apply_damage"):
			d.apply_damage(rake_damage, self)
		recoil = 1.0 # swing the blade clip
		AudioBus.play_synth_at("impact_metal", global_position, -2.0, 0.75)


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
