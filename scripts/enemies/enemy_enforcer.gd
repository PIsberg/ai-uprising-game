class_name EnemyEnforcer
extends EnemyAndroid
## ENFORCER — the AI's armoured riot trooper, built on the mech-police chassis with
## a braced scifi rifle. Tougher and more accurate than a stock android: it holds
## its ground, takes measured bursts, and shrugs off chip damage.

func _ready() -> void:
	super._ready()
	max_health = 210.0
	move_speed = 4.2
	turn_speed = 7.0
	attack_range = 30.0
	preferred_range = 16.0
	hitscan_damage = 11.0
	burst_count = 4
	score_value = 240
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 3.0
