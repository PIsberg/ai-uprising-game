class_name EnemyOptic
extends EnemyAndroid
## OPTICON — a repurposed maintenance unit: a boxy yellow body slung under a single
## glaring red optic, scuttling on spindly tool-legs. It was built to weld and
## repair; now it lances you with its cutting beam. Slow and fragile, but its shots
## sting and it never blinks.

func _ready() -> void:
	super._ready()
	max_health = 95.0
	move_speed = 3.4
	turn_speed = 6.5
	attack_range = 26.0
	preferred_range = 14.0
	hitscan_damage = 14.0
	burst_count = 2
	score_value = 170
	hp.max_health = max_health
	hp.current_health = max_health
