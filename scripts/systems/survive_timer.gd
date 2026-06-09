class_name SurviveTimer
extends Node
## Drives a "hold out for N seconds" task. Counts up only while the game is
## actively playing (not paused / in a menu) and stops once the goal is met.

@export var task_id: String = "survive"
@export var seconds: float = 45.0

func _process(delta: float) -> void:
	if GameState.is_task_done(task_id):
		set_process(false)
		return
	if GameState.current_state == GameState.State.PLAYING:
		GameState.advance_task(task_id, delta)
