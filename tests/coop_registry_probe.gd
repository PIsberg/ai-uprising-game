extends Node3D
## Probe: the co-op PLAYER REGISTRY (GameState.players / nearest_player), stage 1 of
## local co-op. Two real players on a floor:
## (1) players() lists both in player_index order; nearest_player picks by distance
##     and skips a downed player while a living one exists;
## (2) a robot targets the nearer player, and switches when that one goes down;
## (3) a laser gate with a player standing in each half of its live beam hurts both;
## (4) an exploding barrel shakes every player in reach, not only the first;
## (5) no script reaches for "the" player with get_first_node_in_group("player")
##     outside ALLOWED (the registry itself, and the stages still to come: the HUD
##     follows its own player in stage 3, GameState's run bookkeeping in stage 4).
##   godot --headless --path . --audio-driver Dummy res://tests/coop_registry_probe.tscn

const PLAYER := "res://scenes/player/player.tscn"
const ANDROID := "res://scenes/enemies/android.tscn"
## Files still allowed to look the player up directly, each with why.
const ALLOWED := {
	"scripts/autoload/game_state.gd": "the registry, and run bookkeeping (stage 4)",
	"scripts/ui/hud.gd": "the HUD binds to its own player in stage 3",
}
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _wait_game(seconds: float) -> void:
	var acc := 0.0
	while acc < seconds:
		await get_tree().physics_frame
		acc += get_physics_process_delta_time()

func _player(index: int, pos: Vector3) -> CharacterBody3D:
	var p: CharacterBody3D = (load(PLAYER) as PackedScene).instantiate()
	p.set("player_index", index)
	add_child(p)
	p.global_position = pos
	return p

func _scan(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			var path := dir.path_join(f)
			var text := FileAccess.get_file_as_string(path)
			if text.contains("get_first_node_in_group(\"player\")"):
				out.append(path.trim_prefix("res://"))
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), out)

func _run() -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80, 1, 80)
	cs.shape = bs
	cs.position.y = -0.5
	sb.add_child(cs)
	add_child(sb)
	GameState.set_state(GameState.State.PLAYING)
	var p1 := _player(0, Vector3(-6, 0.1, 0))
	var p2 := _player(1, Vector3(6, 0.1, 0))
	await _wait_game(0.3)

	# 1. The registry.
	var ps: Array = GameState.players()
	_check("players() lists both, in index order", ps.size() == 2 and ps[0] == p1 and ps[1] == p2)
	_check("nearest_player picks by distance", GameState.nearest_player(Vector3(5, 0, 0)) == p2 and GameState.nearest_player(Vector3(-5, 0, 0)) == p1)

	# 2. A robot targets the nearer player.
	var bot: EnemyBase = (load(ANDROID) as PackedScene).instantiate()
	add_child(bot)
	bot.global_position = Vector3(4, 0, -6)
	await _wait_game(0.5)
	_check("a robot targets the nearer player", bot.call("_find_player") == p2)
	(p2.get("hp") as Damageable).apply_damage(99999.0, null, false, null, true)
	await _wait_game(0.3)
	_check("nearest_player skips a downed player", GameState.nearest_player(Vector3(5, 0, 0)) == p1)
	_check("the robot turns to the one still standing", bot.call("_find_player") == p1)
	(p2.get("hp") as Damageable).current_health = (p2.get("hp") as Damageable).max_health
	p2.set("_dead", false)

	# 3. A laser gate hurts both players standing in its beam.
	var gate := LaserGate.new()
	gate.axis = "x"
	gate.width = 10.0
	gate.period = 1000.0
	add_child(gate)
	gate.global_position = Vector3(0, 0, 12)
	p1.global_position = Vector3(-3, 0.1, 12)
	p2.global_position = Vector3(3, 0.1, 12)
	var h1 := (p1.get("hp") as Damageable).current_health
	var h2 := (p2.get("hp") as Damageable).current_health
	await _wait_game(1.2)
	_check("a laser gate hurts both players in its beam",
		(p1.get("hp") as Damageable).current_health < h1 and (p2.get("hp") as Damageable).current_health < h2,
		"%.0f->%.0f, %.0f->%.0f" % [h1, (p1.get("hp") as Damageable).current_health, h2, (p2.get("hp") as Damageable).current_health])
	gate.queue_free()

	# 4. A barrel blast shakes both players in reach.
	p1.global_position = Vector3(-4, 0.1, 25)
	p2.global_position = Vector3(4, 0.1, 25)
	await _wait_game(0.3)
	var shook := {}
	for p in [p1, p2]:
		shook[p] = 0.0
	var barrel: Node3D = (load("res://scenes/props/barrel.tscn") as PackedScene).instantiate()
	add_child(barrel)
	barrel.global_position = Vector3(0, 0, 30)
	await _wait_game(0.1)
	# shake() keeps the larger of the current and the new amount, so shake left
	# over from the laser hits above could outlast the blast's own (CI read
	# 0.53 -> 0.52 on player two). Start both from rest: this measures the blast.
	for p in [p1, p2]:
		p.set("_shake_amount", 0.0)
	var s1 := float(p1.get("_shake_amount"))
	var s2 := float(p2.get("_shake_amount"))
	(barrel.get("hp") as Damageable).apply_damage(9999.0, null)
	await get_tree().process_frame
	_check("a barrel blast shakes every player in reach", float(p1.get("_shake_amount")) > s1 and float(p2.get("_shake_amount")) > s2,
		"%.2f->%.2f, %.2f->%.2f" % [s1, float(p1.get("_shake_amount")), s2, float(p2.get("_shake_amount"))])

	# 5. No stray single-player lookups.
	var hits: Array = []
	_scan("res://scripts", hits)
	var stray := hits.filter(func(f): return not ALLOWED.has(f))
	_check("no script outside the registry looks up \"the\" player", stray.is_empty(), str(stray))

	GameState.set_state(GameState.State.MENU)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
