class_name EnemyGunslinger
extends EnemyAndroid
## GUNSLINGER — a brass steampunk automaton with a heavy revolver arm. It fires
## single, hard-hitting slugs on a slow cadence rather than spraying, and dances
## to the side between shots. Punishing if you stand still; easy to bait into a
## wasted shot.

func _ready() -> void:
	super._ready()
	max_health = 130.0
	move_speed = 4.8
	turn_speed = 8.0
	attack_range = 32.0
	preferred_range = 18.0
	hitscan_damage = 26.0
	burst_count = 1       # one heavy slug
	score_value = 200
	hp.max_health = max_health
	hp.current_health = max_health
