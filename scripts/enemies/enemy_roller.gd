class_name EnemyRoller
extends EnemyDog
## ROLLER — a monowheel brawler: a gold drum balanced on a single fat wheel, with
## whipping spring-arms. It rolls in fast and rams, knocking you back. Tougher than
## the K-9 hound but a touch slower to turn, so circle-strafe it.

func _ready() -> void:
	super._ready()
	bite_damage = 24.0
	max_health = 150.0
	move_speed = 8.0
	turn_speed = 7.5
	attack_range = 3.4
	score_value = 175
	stagger_threshold = 46.0
	hp.max_health = max_health
	hp.current_health = max_health
