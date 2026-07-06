class_name EnemyGunslinger
extends EnemyAndroid
## GUNSLINGER — a brass steampunk automaton with a heavy revolver arm. It fires
## single, hard-hitting slugs on a slow cadence rather than spraying, and dances
## to the side between shots. Punishing if you stand still; easy to bait into a
## wasted shot.

func _ready() -> void:
	super._ready()
	max_health = 130.0
	move_speed = 6.2      # lean, nimble duelist — quicker than a standard android
	turn_speed = 9.5
	attack_range = 32.0
	preferred_range = 18.0
	hitscan_damage = 26.0
	burst_count = 1       # one heavy slug
	score_value = 200
	hp.max_health = max_health
	hp.current_health = max_health

## Duelist footwork: every slug is punctuated by a sidestep, so the gunslinger is
## always sliding to a new angle between shots — the "dances to the side" the
## brass-revolver model promises — instead of planting like a stock android. It
## reuses the android's own juke movement by kicking its dodge state on each shot
## (alternating direction for a deliberate weave, not the occasional random juke).
func _start_burst() -> void:
	super._start_burst()
	_dodge_dir = -_dodge_dir
	_dodge_time = 0.4
	_dodge_cd = 0.8   # space the next natural juke so the weave stays per-shot, not constant
