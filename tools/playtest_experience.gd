extends Node3D
## Experience playtest: plays the opening campaign level like a player would —
## real input actions, aim assisted at the nearest hostile — and photographs
## every beat (first impression, first contact, getting hit, kill feedback,
## objective work, alarm wave, low HP, extraction). Prints a state line per
## beat so pacing (kills/tasks/hp over time) can be read from the log.
##   godot --path . tools/playtest_experience.tscn

const OUT := "res://docs/screenshots/playtest"
const LEVEL := "suburb"

var _player: CharacterBody3D
var _cam: Camera3D
var _head: Node3D
var _t0 := 0.0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var lvl: Node = load("res://scenes/levels/level_%s.tscn" % LEVEL).instantiate()
	add_child(lvl)
	_run.call_deferred()

func _state(tag: String) -> void:
	var hpv = _player.hp.health if (_player and _player.hp) else -1
	print("BEAT %-16s t=%5.1f hp=%s kills=%d tasks=%s" % [tag,
		Time.get_ticks_msec() / 1000.0 - _t0, hpv, GameState.kills,
		str(GameState.level_tasks.map(func(t): return "%s%s" % [t["id"], "+" if t["done"] else "-"]))])

func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, name])
	_state(name)

func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var bd := 1e9
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and (e as EnemyBase).hp and (e as EnemyBase).hp.is_alive():
			var d: float = _player.global_position.distance_to((e as Node3D).global_position)
			if d < bd:
				bd = d
				best = e
	return best

## Face the target: yaw on the player body, pitch on the head (like mouselook).
func _aim_at(target: Vector3) -> void:
	var eye := _cam.global_position
	var d := target - eye
	_player.rotation.y = atan2(-d.x, -d.z)
	var flat := Vector2(d.x, d.z).length()
	if _head:
		_head.rotation.x = clampf(atan2(d.y, flat), -1.2, 1.2)

## Fight until `want_kills` total kills (or timeout): aim at the nearest live
## hostile, close distance when far, strafe when near, trigger in bursts.
func _fight_until(want_kills: int, timeout: float) -> void:
	var t := 0.0
	while GameState.kills < want_kills and t < timeout:
		if _player.hp and not _player.hp.is_alive():
			print("BOT DIED during fight (killer=", GameState.last_killer, ")")
			break
		var e := _nearest_enemy()
		if e == null:
			break
		var aim: Vector3 = e.global_position + Vector3(0, 0.6, 0)
		_aim_at(aim)
		var dist: float = _player.global_position.distance_to(e.global_position)
		Input.action_release("move_left")
		if dist > 14.0:
			Input.action_press("move_forward")
		else:
			Input.action_release("move_forward")
			Input.action_press("move_left") # strafe under fire
		Input.action_press("fire")
		await get_tree().create_timer(0.25).timeout
		Input.action_release("fire")
		await get_tree().create_timer(0.08).timeout
		t += 0.33
	for a in ["move_forward", "move_left", "fire"]:
		Input.action_release(a)

## Walk to a world position (simple steering; gives up on timeout).
func _walk_to(target: Vector3, timeout: float) -> void:
	var t := 0.0
	while _player.global_position.distance_to(target) > 2.0 and t < timeout:
		_aim_at(target + Vector3(0, 1.2, 0))
		Input.action_press("move_forward")
		Input.action_press("sprint")
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	Input.action_release("move_forward")
	Input.action_release("sprint")

func _run() -> void:
	await get_tree().create_timer(2.5).timeout # build + navmesh + spawns
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		print("NO PLAYER"); get_tree().quit(1); return
	_cam = _player.get("camera")
	_head = _player.get_node_or_null("Head")
	_t0 = Time.get_ticks_msec() / 1000.0
	GameState.set_state(GameState.State.PLAYING)
	_shot("01_first_impression")
	# First contact: fight to 3 kills.
	await _fight_until(3, 30.0)
	_shot("02_first_contact")
	# Keep fighting into the thick of it.
	await _fight_until(8, 40.0)
	_shot("03_mid_fight")
	# Objective: walk to the sabotage relay and hold interact-fire on it.
	var con := get_tree().get_first_node_in_group("objective")
	if con:
		await _walk_to((con as Node3D).global_position, 14.0)
		_shot("04_at_objective")
		_aim_at((con as Node3D).global_position + Vector3(0, 1, 0))
		var t := 0.0
		while not GameState.is_task_done("sabotage") and t < 12.0:
			await get_tree().create_timer(0.2).timeout
			t += 0.2
		_shot("05_objective_done")
	# The alarm wave answers: capture the reaction fight.
	await get_tree().create_timer(1.5).timeout
	_shot("06_alarm_wave")
	await _fight_until(GameState.kills + 2, 25.0)
	_shot("07_wave_fight")
	_state("END")
	print("PLAYTEST DONE kills=", GameState.kills, " hp=", _player.hp.health if _player.hp else -1)
	get_tree().quit()
