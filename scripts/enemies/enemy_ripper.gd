class_name EnemyRipper
extends EnemyAndroid
## RIPPER — a walking minigun platform. It plants at mid range and saws off long,
## rapid bursts of bolts, suppressing you behind cover. Lightly armoured for its
## firepower, so flank it while it's committed to a burst. The chassis is rigged,
## so its idle/walk clips drive the legs.

func _ready() -> void:
	super._ready()
	max_health = 170.0
	move_speed = 3.6
	turn_speed = 6.0
	attack_range = 28.0
	preferred_range = 15.0
	hitscan_damage = 5.0
	burst_count = 12      # a long minigun saw
	score_value = 230
	hp.max_health = max_health
	hp.current_health = max_health
