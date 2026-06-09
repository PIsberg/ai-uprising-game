class_name Objective
extends Area3D

signal completed

@export var objective_text: String = "Reach the extraction point"
@export var requires_all_enemies_dead: bool = false
@export var auto_complete_on_player_enter: bool = true

var _completed: bool = false

func _ready() -> void:
	collision_layer = 64
	collision_mask = 2 # player
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _completed:
		return
	if not body.is_in_group("player"):
		return
	if requires_all_enemies_dead and get_tree().get_nodes_in_group("enemy").any(func(e): return e is EnemyBase and (e as EnemyBase).hp.is_alive()):
		return
	if auto_complete_on_player_enter:
		complete()

func complete() -> void:
	if _completed:
		return
	_completed = true
	completed.emit()
	GameState.on_level_complete()
