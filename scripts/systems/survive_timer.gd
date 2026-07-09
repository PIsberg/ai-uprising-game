class_name SurviveTimer
extends Node
## Drives a "hold out for N seconds" task. Counts up only while the game is
## actively playing (not paused / in a menu) and stops once the goal is met.
##
## Optional escalating WAVES turn the hold into a real climax instead of a
## countdown you can wait out behind cover. Each entry is
##   {"at": seconds_elapsed, "label": "SECOND WAVE",
##    "enemies": [<enemy specs>], "supplies": [<pickup specs>]}
## and fires once when the clock crosses `at`. The enemy specs match the level
## def's "enemies"/"reinforce" format, and are handed to the level builder's
## reinforcement spawner — so they get the same spawn FX and difficulty scaling
## as any placed enemy. "supplies" are optional pickup drops ({type, pos}, like
## the def's "pickups") that keep a long hold sustainable; place them somewhere
## costly to reach and the resupply becomes a decision rather than a freebie.
## Waves at/after `seconds` never fire (the hold is over).

@export var task_id: String = "survive"
@export var seconds: float = 45.0

## Authored waves, ascending by "at". Empty = a plain countdown (old behaviour).
@export var waves: Array = []

## A wave came due. The level builder spawns its enemies + supplies; the HUD
## announces the label so the escalation reads as intentional.
signal wave_due(wave: Dictionary)

var _elapsed: float = 0.0
var _next_wave: int = 0

func _ready() -> void:
	# Author order is the contract, but a mis-ordered def would silently skip
	# waves (we only ever look at _next_wave), so sort defensively.
	waves = waves.duplicate()
	waves.sort_custom(func(a, b): return float(a.get("at", 0.0)) < float(b.get("at", 0.0)))

func _process(delta: float) -> void:
	if GameState.is_task_done(task_id):
		set_process(false)
		return
	if GameState.current_state != GameState.State.PLAYING:
		return
	GameState.advance_task(task_id, delta)
	_elapsed += delta
	# Fire every wave the clock just crossed (a long frame can cross two).
	while _next_wave < waves.size() and _elapsed >= float(waves[_next_wave].get("at", 0.0)):
		var w: Dictionary = waves[_next_wave]
		_next_wave += 1
		wave_due.emit(w)
