class_name BonusObjective
extends Node
# @lat: [[level-system#Bonus Objectives]]
## A level's optional challenge (def "bonus"): a way of winning the level that
## pays extra score. It is NEVER part of the exit lock: it lives in
## GameState.level_bonus, not level_tasks, so a failed bonus cannot seal a
## level, and the mission-arc and task probes never see it.
##
## It stays live until the level's tasks are all done (won, +score) or the
## player breaks its rule (failed, for the rest of the level: dying does not
## give it back, or a death would be a free retry).
##
## Kinds:
##   ghost: trip no vision-scanner alarm (levels with "scanners").
##   dry:   take no damage from a hazard bed, flood included (levels with "lava").
##   deathless: finish without dying once (the boss levels).

@export var kind: String = "ghost"
@export var label: String = ""
@export var score: int = 500

var _player_hp: Damageable

func _ready() -> void:
	GameState.set_bonus(label, score)
	_hook.call_deferred()

## Scanners and the player are built after the tasks: connect a frame later.
func _hook() -> void:
	match kind:
		"ghost":
			for sc in get_tree().get_nodes_in_group("scanner"):
				if sc.has_signal("alarmed"):
					sc.alarmed.connect(_on_broken)
		"deathless":
			GameState.player_died.connect(_on_broken)
		"dry":
			var p := get_tree().get_first_node_in_group("player")
			if p:
				_player_hp = p.get_node_or_null("Damageable") as Damageable
				if _player_hp:
					_player_hp.damaged.connect(_on_player_damaged)

func _on_player_damaged(_amount: float, source: Node) -> void:
	if is_instance_valid(source) and source.is_in_group("hazard"):
		_on_broken()

func _on_broken() -> void:
	if GameState.level_bonus.get("state", "") == "live":
		GameState.bonus_fail()

func _process(_delta: float) -> void:
	if GameState.level_bonus.get("state", "") != "live":
		set_process(false)
		return
	if not GameState.level_tasks.is_empty() and GameState.all_tasks_done():
		GameState.bonus_win()
		set_process(false)
