class_name EnemyStrider
extends EnemyBase
## STRIDER — a chicken-walker sentry bot: a domed chassis with a single hostile
## red cyclops eye, raptor-stance legs and a chin gun. A mid-range trooper that
## strides in on its back-jointed legs and rakes the player with bursts of energy
## bolts, keeping its distance. Real model: a CC0 Quaternius robot (RobotModel on
## $Model drives the Run/Shoot/Idle clips).

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")

@export var proj_speed: float = 38.0
@export var proj_damage: float = 9.0
@export var burst_count: int = 3
@export var burst_interval: float = 0.09

var _burst_left: int = 0
var _burst_t: float = 0.0

@onready var _eye_light: OmniLight3D = $EyeLight

func _ready() -> void:
	super._ready()
	max_health = 95.0
	move_speed = 5.0
	turn_speed = 8.0
	sight_range = 40.0
	sight_angle_deg = 220.0
	attack_range = 30.0
	preferred_range = 16.0
	attack_cooldown = 2.0
	telegraph_time = 0.0 # a strafing chin-gun fires on cadence — the generic wind-up + strafing left it barely landing a shot
	score_value = 140
	head_radius = 0.5
	combat_strafe = true # circle-strafe while shooting (and bank into it)
	hp.max_health = max_health
	hp.current_health = max_health

func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	if _eye_light:
		# Red eye throbs, spikes bright with each burst, flares when closing in.
		_eye_light.light_energy = 1.2 + sin(_state_timer * 3.0) * 0.4 + recoil * 3.0 \
			+ (2.0 if is_enraged() else 0.0)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _burst_left > 0:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_fire_one()
			_burst_left -= 1
			_burst_t = burst_interval

## Kick off a burst — the actual bolts stream out in _physics_process.
func _perform_attack() -> void:
	if target == null:
		return
	_burst_left = burst_count
	_burst_t = 0.0
	recoil = 1.0 # plays the Shoot clip via RobotModel

func _fire_one() -> void:
	if target == null or not is_instance_valid(target):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var origin: Vector3 = muzzle.global_position if muzzle else global_position + Vector3.UP * 0.9
	var proj := PROJECTILE.instantiate()
	scene.add_child(proj)
	(proj as Node3D).global_position = origin
	var dir := (target.global_position + Vector3.UP * 0.6 - origin).normalized()
	dir = scatter_aim(dir, 2.0)
	if proj.has_method("launch"):
		proj.launch(dir * proj_speed, self, proj_damage, 0.0, 0.0)
	recoil = 1.0
	_muzzle_flash()
	AudioBus.play_synth_at("drone_shot", origin, -3.0, randf_range(0.92, 1.04))
