class_name EnemyDog
extends EnemyBase
## K-9 HUNTER — a four-legged robot attack-hound. Very fast, hunts in packs,
## sprints the gap and lunges into a bite. Fragile but relentless. Built model:
## assets/models/robots/robot_dog.glb (RobotModel leans it; no walk rig).

@export var bite_damage: float = 16.0

func _ready() -> void:
	max_health = 72.0
	move_speed = 9.2
	turn_speed = 11.0
	sight_range = 38.0
	sight_angle_deg = 230.0
	attack_range = 3.2
	preferred_range = 1.3
	attack_cooldown = 1.0
	attack_lunge_speed = 15.0
	telegraph_time = 0.22
	score_value = 120
	stagger_threshold = 28.0
	super._ready()

func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= attack_range * 1.5:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(bite_damage, self)
		AudioBus.play_synth_at("impact_metal", global_position, -6.0, 1.9)
	_attack_lunge()
