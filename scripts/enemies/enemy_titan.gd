class_name EnemyTitan
extends EnemyColossus
## Second campaign mega-boss. Mechanically a Colossus (artillery / chest beam /
## ground-slam, HUD boss bar, cinematic entrance) but a distinct fighter: a
## taller, lankier warframe — the "Giant Robot" model (CC-BY, Dann Beeson) —
## tuned faster and a touch less armored, so it strides and repositions where
## GOLIATH lumbers. The model has no rig, so RobotModel drives no clips; its
## advance is velocity + the procedural sway already on the chassis.

func _ready() -> void:
	super._ready()
	# Re-skin identity + a faster, glassier tuning (changed synchronously here,
	# before the deferred boss announcement reads them).
	boss_name = "PROMETHEUS-0"
	max_health = 2600.0
	move_speed = 3.4   # a strider, not a siege engine
	turn_speed = 2.2
	score_value = 3200
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 6.0
