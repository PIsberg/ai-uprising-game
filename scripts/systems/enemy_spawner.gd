class_name EnemySpawner
extends Marker3D

@export var enemy_scene: PackedScene
@export var spawn_on_ready: bool = true
@export var spawn_delay: float = 0.0
@export var trigger_radius: float = 0.0 # 0 = no trigger, spawn on ready/delay

var _spawned: bool = false

func _ready() -> void:
	if spawn_on_ready:
		if spawn_delay > 0.0:
			await get_tree().create_timer(spawn_delay).timeout
		_spawn()
	elif trigger_radius > 0.0:
		set_process(true)

func _process(_delta: float) -> void:
	if _spawned:
		set_process(false)
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	if (players[0] as Node3D).global_position.distance_to(global_position) < trigger_radius:
		_spawn()

func _spawn() -> void:
	if _spawned or enemy_scene == null:
		return
	_spawned = true
	var e := enemy_scene.instantiate() as Node3D
	_apply_difficulty(e)
	# A small difficulty-scaled share of spawns come up elite (pre-add, so the
	# boosted exports land before the enemy's _ready wiring).
	Elite.maybe_apply(e)
	# current_scene is at the world origin, so local == global here. Setting the
	# position before a *deferred* add_child avoids the "parent is busy setting
	# up children" failure when spawning during the level's own _ready().
	e.position = global_position
	get_tree().current_scene.add_child.call_deferred(e)

## Scale this enemy's strength to the campaign difficulty BEFORE it enters the
## tree, so EnemyBase._ready reads the adjusted stats. Set on the export fields
## (not the live Damageable) so the standard _ready wiring picks them up.
func _apply_difficulty(e: Node3D) -> void:
	if not (e is EnemyBase):
		return
	var gs := get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("difficulty_config"):
		return
	var cfg: Dictionary = gs.difficulty_config()
	var eb := e as EnemyBase
	# Health/speed/cadence via the _*_mult fields (applied after the subclass
	# _ready sets its base), so difficulty scaling isn't wiped by the subclass's
	# own `max_health = N` / `move_speed = N` / `attack_cooldown = N`.
	eb._health_mult *= cfg.get("health_mult", 1.0)
	eb._cooldown_mult *= cfg.get("cooldown_mult", 1.0)
	eb._speed_mult *= cfg.get("speed_mult", 1.0)
	eb.reaction_time *= cfg.get("reaction_mult", 1.0) # not clobbered (no subclass sets it)
