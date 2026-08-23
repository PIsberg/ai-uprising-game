extends Node3D
## Headless auto-player difficulty sweep. For a representative set of campaign
## levels, drops a bot in (real input actions, aim-assisted at the nearest live
## hostile) and lets it fight toward enemies then push toward the exit for a fixed
## budget. Reports one line per level so the difficulty curve can be read from the
## log: kills, HP% remaining, deaths, whether it made progress.
## The bot's skill is fixed, so the SIGNAL is cross-level comparison — a level
## where the bot dies fast / makes no kills is a spike or softlock; one it clears
## at full HP is trivial. No screenshots (fully headless).
## Run: godot --headless --path . res://tests/pacing_sweep.tscn

# Spread across the campaign arc: early, mid, boss, hazard, late, finale.
const IDS := ["gpt", "suburb", "convoy", "claude", "overseer", "alien",
	"frostbreak", "desert", "neon", "lava_world", "titan", "archon"]

const BUDGET := 26.0   ## seconds of active play per level
const HP_MAX := 200.0

var _lvl: Node
var _player: CharacterBody3D
var _cam: Node3D
var _head: Node3D

func _ready() -> void:
	for id in IDS:
		await _play(id)
	print("PACING_SWEEP_DONE")
	get_tree().quit()

func _play(id: String) -> void:
	var path := "res://scenes/levels/level_%s.tscn" % id
	if not ResourceLoader.exists(path):
		print("PACE %-12s SKIP (no scene)" % id); return
	# Fresh run state each level.
	GameState.kills = 0
	_lvl = (load(path) as PackedScene).instantiate()
	add_child(_lvl)
	await get_tree().create_timer(2.4).timeout  # build + navmesh + spawns
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		print("PACE %-12s NO-PLAYER" % id); await _teardown(); return
	_cam = _player.get("camera")
	_head = _player.get_node_or_null("Head")
	GameState.set_state(GameState.State.PLAYING)
	var hp: Damageable = _player.get("hp")
	var start_hp: float = hp.current_health if hp else -1.0

	var t := 0.0
	var died := false
	var death_t := -1.0
	var min_hp := start_hp
	while t < BUDGET:
		if hp and not hp.is_alive():
			if not died:
				died = true; death_t = t
			break
		var e := _nearest_enemy()
		if e != null:
			var aim: Vector3 = (e as Node3D).global_position + Vector3(0, 0.6, 0)
			_aim_at(aim)
			var dist: float = _player.global_position.distance_to((e as Node3D).global_position)
			if dist > 14.0:
				Input.action_press("move_forward"); Input.action_release("move_left")
			else:
				Input.action_release("move_forward"); Input.action_press("move_left")
			Input.action_press("fire")
			await get_tree().create_timer(0.22).timeout
			Input.action_release("fire")
			await get_tree().create_timer(0.06).timeout
			t += 0.28
		else:
			# No live enemy in sight — nudge toward the exit to trigger the next wave.
			var def: Dictionary = LevelDefs.get_def(id)
			var goal: Vector3 = def.get("exit", def.get("spawn", _player.global_position))
			_aim_at(goal + Vector3(0, 1.2, 0))
			Input.action_press("move_forward"); Input.action_press("sprint")
			await get_tree().create_timer(0.2).timeout
			t += 0.2
		if hp:
			min_hp = minf(min_hp, hp.current_health)
	for a in ["move_forward", "move_left", "fire", "sprint"]:
		Input.action_release(a)

	var end_hp: float = hp.current_health if (hp and hp.is_alive()) else 0.0
	var hp_pct := 100.0 * end_hp / maxf(start_hp, 1.0)
	var min_pct := 100.0 * maxf(min_hp, 0.0) / maxf(start_hp, 1.0)
	var verdict := "DIED@%.0fs" % death_t if died else "survived"
	print("PACE %-12s kills=%2d  hp=%5.1f%%  minHP=%5.1f%%  %s" % [
		id, GameState.kills, hp_pct, min_pct, verdict])
	await _teardown()

## MUST be awaited. It is a coroutine, and without the await the next level began
## building while this one's nodes were still in the "player"/"enemy" groups — so
## the next measurement picked up the PREVIOUS level's already-dead player and
## logged it as DIED@0s. Every reading after the first death was junk.
func _teardown() -> void:
	if is_instance_valid(_lvl):
		_lvl.queue_free()
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e): e.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _nearest_enemy() -> Node:
	var best: Node = null
	var bd := 1e9
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and (e as EnemyBase).hp and (e as EnemyBase).hp.is_alive():
			var d: float = _player.global_position.distance_to((e as Node3D).global_position)
			if d < bd: bd = d; best = e
	return best

func _aim_at(target: Vector3) -> void:
	if _cam == null or not (_cam is Node3D):
		return
	var eye: Vector3 = (_cam as Node3D).global_position
	var d := target - eye
	_player.rotation.y = atan2(-d.x, -d.z)
	var flat := Vector2(d.x, d.z).length()
	if _head:
		_head.rotation.x = clampf(atan2(d.y, flat), -1.2, 1.2)
