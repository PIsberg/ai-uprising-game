class_name EnemyReaper
extends EnemyBase
## Fast melee killer: sprints at the player and lunges into a slashing strike.
## Fragile but lethal up close. Visuals come from a real robot model in
## reaper.tscn (RobotModel handles animation + the red menace tint).

@export var slash_damage: float = 22.0


func _ready() -> void:
	max_health = 62.0
	move_speed = 8.6
	turn_speed = 9.0
	sight_range = 34.0
	sight_angle_deg = 200.0
	attack_range = 3.0
	preferred_range = 1.5
	attack_cooldown = 1.1
	attack_lunge_speed = 12.0
	score_value = 130
	stagger_threshold = 40.0
	super._ready()


func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= attack_range * 1.4:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(slash_damage, self)
		AudioBus.play_synth_at("impact_metal", global_position, -6.0, 1.6)
	_attack_lunge()
