class_name EnemyHowitzer
extends EnemyBase
## HOWITZER — a four-legged artillery walker (assets/models/robots/
## walking_robot_gun.glb): a long-barrelled cannon slung over four bladed
## crab-legs, antennae whipping. It stalks the long sightlines, PLANTS, charges
## with a rising whine, and sends a heavy ballistic shell arcing at you —
## the impact throws splash you have to respect even behind thin cover. Slow,
## armoured, and blind up close: get under its barrel and stay there.

const SHELL := preload("res://scenes/weapons/projectile_howitzer.tscn")

@export var shell_damage: float = 40.0
@export var splash_radius: float = 4.5
@export var splash_damage: float = 26.0
@export var shell_speed: float = 32.0
@export var windup: float = 0.9

var _winding: bool = false
var _windup_t: float = 0.0

func _ready() -> void:
	super._ready()
	max_health = 640.0
	move_speed = 2.6
	turn_speed = 2.2
	sight_range = 60.0
	sight_angle_deg = 200.0
	attack_range = 55.0
	preferred_range = 32.0     # artillery keeps its distance
	attack_cooldown = 5.0
	telegraph_time = 0.0       # the audible spin-up IS the telegraph
	score_value = 500
	head_radius = 0.45
	stagger_threshold = 400.0  # a gun carriage doesn't flinch
	flinch_knockback = 0.0
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 6.0

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _winding:
		_windup_t -= delta
		if _windup_t <= 0.0:
			_winding = false
			_fire_shell()

## A committed gun carriage: plants dead-still through the charge and the shot.
func _move_toward(dest: Vector3, delta: float) -> void:
	if _winding:
		_decelerate()
		_face_target(delta)
		return
	super._move_toward(dest, delta)

func _perform_attack() -> void:
	if target == null or _winding:
		return
	_winding = true
	_windup_t = windup
	AudioBus.play_synth_at("charge", global_position, 0.0, 0.55)  # deep breech whine
	_speak("atk", 0.4)

func _fire_shell() -> void:
	if target == null or not is_instance_valid(target) or muzzle == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var proj := SHELL.instantiate()
	scene.add_child(proj)
	(proj as Node3D).global_position = muzzle.global_position
	# Ballistic solve: lead the runner, then hold the barrel high enough that
	# the shell's gravity drop lands the arc on them.
	var aim: Vector3 = target.global_position + Vector3.UP * 0.4
	if "velocity" in target:
		aim += (target.velocity as Vector3) * 0.35
	var dist := muzzle.global_position.distance_to(aim)
	var t := dist / shell_speed
	var gs: float = proj.get("gravity_scale") if proj.get("gravity_scale") != null else 0.3
	aim += Vector3.UP * (0.5 * 9.8 * gs * t * t)
	var dir := (aim - muzzle.global_position).normalized()
	if proj.has_method("launch"):
		proj.launch(dir * shell_speed, self, shell_damage, splash_radius, splash_damage)
	recoil = 1.0
	_muzzle_flash()
	AudioBus.play_synth_at("explosion", muzzle.global_position, -4.0, 1.6)  # sharp muzzle report
	AudioBus.play_synth_at("mech_step", global_position, 0.0, 0.45)         # carriage rocks back
