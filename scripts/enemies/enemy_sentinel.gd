class_name EnemySentinel
extends EnemyBase
## Heavy weapons platform. Slow and very tanky; plants itself at range and lobs
## heavy bolts. Visuals from a real robot model in sentinel.tscn.

@export var proj_speed: float = 34.0
@export var proj_damage: float = 18.0

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")


func _ready() -> void:
	max_health = 185.0
	move_speed = 3.4
	turn_speed = 4.0
	sight_range = 42.0
	sight_angle_deg = 180.0
	attack_range = 34.0
	preferred_range = 22.0
	attack_cooldown = 1.9
	telegraph_time = 0.0 # a planted weapons platform fires on cadence — no generic wind-up (its bolts are the threat)
	score_value = 180
	stagger_threshold = 120.0
	super._ready()


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
