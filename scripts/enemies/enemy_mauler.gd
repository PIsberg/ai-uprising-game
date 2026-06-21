class_name EnemyMauler
extends EnemyBase
## Heavy melee brawler: closes in and slams with both fists. Slow but very tough.
## Visuals from a real robot model in mauler.tscn (RobotModel plays its Punch
## clip on each attack).

@export var slam_damage: float = 34.0


func _ready() -> void:
	max_health = 210.0
	move_speed = 5.0
	turn_speed = 5.5
	sight_range = 32.0
	sight_angle_deg = 180.0
	attack_range = 3.6
	preferred_range = 1.8
	attack_cooldown = 1.5
	attack_lunge_speed = 9.0
	score_value = 175
	stagger_threshold = 130.0
	super._ready()


func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= attack_range * 1.4:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(slam_damage, self)
		AudioBus.play_synth_at("impact_metal", global_position, -4.0, 1.2)
	_attack_lunge()
