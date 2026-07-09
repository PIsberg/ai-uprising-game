class_name EnemySpawner
extends Marker3D

@export var enemy_scene: PackedScene
@export var spawn_on_ready: bool = true
@export var spawn_delay: float = 0.0
@export var trigger_radius: float = 0.0 # 0 = no trigger, spawn on ready/delay

## Squad id. Every spawner sharing a pack_id wakes the instant ANY of them is
## tripped, so a mixed squad arrives together instead of trickling in as the
## player crosses each robot's own trigger circle one at a time. Measured with
## tests/pack_probe before this existed: 29% of encounters were a lone robot and
## 32% were a single chassis type repeated.
@export var pack_id: String = ""

## Seconds between each squadmate materialising. They pour in, they don't pop as
## one wall of robots.
const PACK_STAGGER := 0.13

var _spawned: bool = false
## Claimed for a staggered pack spawn but not yet materialised. Without this a
## second squadmate tripping during the stagger would queue the same robot again.
var _pending: bool = false

func _ready() -> void:
	if pack_id != "":
		add_to_group(_pack_group())
	if spawn_on_ready:
		if spawn_delay > 0.0:
			await get_tree().create_timer(spawn_delay).timeout
		_spawn()
	elif trigger_radius > 0.0:
		set_process(true)

func _pack_group() -> String:
	return "pack_" + pack_id

func _process(_delta: float) -> void:
	if _spawned:
		set_process(false)
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	if (players[0] as Node3D).global_position.distance_to(global_position) < trigger_radius:
		if pack_id != "":
			_trip_pack()
		else:
			_spawn()

## One squadmate saw the player: wake the whole squad, staggered.
func _trip_pack() -> void:
	var i := 0
	for n in get_tree().get_nodes_in_group(_pack_group()):
		if not is_instance_valid(n):
			continue
		var sp := n as EnemySpawner
		if sp == null or sp._spawned or sp._pending:
			continue
		sp._spawn_after(float(i) * PACK_STAGGER)
		i += 1

func _spawn_after(delay: float) -> void:
	if _spawned or _pending:
		return
	_pending = true
	set_process(false)
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if not is_instance_valid(self):
			return
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
	e.position = _clear_spawn_pos()
	get_tree().current_scene.add_child.call_deferred(e)

## Authored spawn points aren't validated against the built level, so one can
## land inside a building/prop box — the enemy is stuck in solid geometry and
## kill_all objectives become impossible. Nudge such a point to the nearest
## clear spot (physics is live by spawn time: spawns are delayed/triggered).
func _clear_spawn_pos() -> Vector3:
	var pos := global_position
	var space := get_world_3d().direct_space_state
	if _point_clear(space, pos):
		return pos
	for r: float in [2.0, 3.5, 5.5, 8.0]:
		for i in 10:
			var ang := TAU * float(i) / 10.0
			var p: Vector3 = pos + Vector3(cos(ang), 0.0, sin(ang)) * r
			if _point_clear(space, p):
				push_warning("Enemy spawn %s buried in geometry; relocated to %s" % [pos, p])
				return p
	return pos

func _point_clear(space: PhysicsDirectSpaceState3D, pos: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = pos + Vector3(0, 1.0, 0)
	q.collision_mask = 1
	return space.intersect_point(q, 1).is_empty()

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
	# Campaign-depth ramp: enemies get tougher (and a touch faster on the trigger)
	# the deeper you are, sized to offset the player's permanent power creep so
	# late levels don't trivialize. No-ops off-campaign. Bosses are exempt — they're
	# hand-tuned HP bags and the tier mult already scales them; ramping on top would
	# turn the climax into a slog.
	var is_boss: bool = enemy_scene != null and gs.has_method("is_boss_scene") \
			and gs.is_boss_scene(enemy_scene.resource_path)
	if not is_boss and gs.has_method("campaign_health_mult"):
		eb._health_mult *= gs.campaign_health_mult()
		eb._cooldown_mult *= gs.campaign_cadence_mult()
