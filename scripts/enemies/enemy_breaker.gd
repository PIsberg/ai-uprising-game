class_name EnemyBreaker
extends EnemyDrone
## BREAKER — a hovering bronze sphere-bot built around a glowing core, dragging a
## massive piston hammer. It floats in, bobbing, then dives to slam you with the
## hammer before drifting back up out of reach. Pure melee — shoot it down before
## it closes.

@export var smash_damage: float = 26.0

func _ready() -> void:
	super._ready()
	max_health = 150.0
	move_speed = 6.0
	sight_range = 38.0
	attack_range = 3.6
	preferred_range = 3.2
	attack_cooldown = 1.1
	hover_height = 2.0
	hover_amplitude = 0.5
	score_value = 220
	drops_loot = true
	hp.max_health = max_health
	hp.current_health = max_health

## Hammer slam instead of the drone's projectile.
func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	recoil = 1.0
	if global_position.distance_to(target.global_position) <= attack_range * 1.3:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(smash_damage, self)
		AudioBus.play_synth_at("impact_metal", global_position, -2.0, 0.8)
