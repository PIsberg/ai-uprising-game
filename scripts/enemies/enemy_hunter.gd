class_name EnemyHunter
extends EnemyBase
## Sleek, fast skirmisher with shoulder cannons. Circle-strafes at mid range and
## fires rapid bolt bursts. Visuals from a real robot model in hunter.tscn.

@export var proj_speed: float = 46.0
@export var proj_damage: float = 7.0
@export var burst_count: int = 3

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")

var _burst_left: int = 0
var _burst_t: float = 0.0


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
	combat_strafe = true # circle-strafe skirmisher: stays mobile + banks into it (was a static plinker, unlike the stationary android)
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
