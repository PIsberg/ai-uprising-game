class_name EnemyServer
extends EnemyBase
## MAITRE-D' — a cafe serving robot turned sinister. Trundles in on its wheeled
## base, then swings its serving trays like cleavers, bashing the player back.
## Slow but tanky and heavy-hitting. Built model:
## assets/models/robots/serving_bot.glb (RobotModel leans it; no walk rig).
##
## Signature move: CLEAVER SERVICE — outside tray reach it hurls spinning
## serving-cleavers, so closing on it (or fleeing it) is never free.

@export var bash_damage: float = 26.0
@export var cleaver_damage: float = 16.0
@export var cleaver_speed: float = 17.0
@export var cleaver_cooldown: float = 2.4

var _cleaver_cd: float = 0.0

func _ready() -> void:
	max_health = 155.0
	move_speed = 3.3
	turn_speed = 4.2
	sight_range = 30.0
	sight_angle_deg = 180.0
	attack_range = 3.4
	preferred_range = 1.8
	attack_cooldown = 1.8
	attack_lunge_speed = 6.0
	telegraph_time = 0.45
	score_value = 150
	stagger_threshold = 52.0
	super._ready()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state == State.DEAD:
		return
	_cleaver_cd = maxf(0.0, _cleaver_cd - delta)
	if target and is_instance_valid(target) and _cleaver_cd <= 0.0 \
			and state in [State.CHASE, State.ATTACK] and _can_see(target):
		var dist := global_position.distance_to(target.global_position)
		if dist > attack_range * 1.2 and dist < 16.0:
			_cleaver_cd = cleaver_cooldown
			recoil = 0.8
			var from := global_position + Vector3.UP * 1.4
			ThrownCleaver.throw_at(get_tree().current_scene, from,
				target.global_position + Vector3.UP * 0.8, cleaver_speed, cleaver_damage)
			AudioBus.play_synth_at("impact_metal", from, -9.0, 2.4)

func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= attack_range * 1.4:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(bash_damage, self)
		if target.has_method("shake"):
			target.shake(0.45)
		# A heavy tray-swing knocks the player back off their feet.
		if "velocity" in target and target is Node3D:
			var away: Vector3 = (target as Node3D).global_position - global_position
			away.y = 0.0
			if away.length() > 0.1:
				target.velocity += away.normalized() * 7.5 + Vector3.UP * 2.5
		AudioBus.play_synth_at("impact_metal", global_position, -3.0, 0.8)
	_attack_lunge()
