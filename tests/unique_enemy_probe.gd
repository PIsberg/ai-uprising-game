extends Node3D
## Verifies the batch-5 signature behaviors on the REAL AI (flat floor + player
## proxy, same harness as enemy_combat_probe):
##  hunter  — blade dash fires (lunge engaged + cooldown reset) and can rake
##  raptor  — commits a strafing run (_run_t) and returns to the hover fight
##  ripper  — spin-up gate first (_spinning), then the 12-round saw
##  sentinel— mortar salvo drops real EnemyBomb shells (bomb_every forced to 1)
##  warbot  — FURIOUS flips below 45% HP and the twin cross-fire deals damage

var _player: Node3D
var _php

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fb := BoxShape3D.new(); fb.size = Vector3(80, 1, 80)
	fcs.shape = fb
	floor_body.add_child(fcs)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	_player = StaticBody3D.new()
	_player.add_to_group("player")
	_player.collision_layer = 2
	var pcs := CollisionShape3D.new()
	var pc := CapsuleShape3D.new(); pc.radius = 1.0; pc.height = 2.6
	pcs.shape = pc
	_player.add_child(pcs)
	_player.position = Vector3(0, 1, 0)
	_php = Node.new()
	_php.set_script(load("res://scripts/systems/damageable.gd"))
	_php.name = "Damageable"
	_php.set("max_health", 100000.0)
	_player.add_child(_php)
	add_child(_player)
	_run.call_deferred()

func _spawn(name: String, dist: float, fly: bool) -> Node3D:
	var bot: Node3D = load("res://scenes/enemies/%s.tscn" % name).instantiate()
	add_child(bot)
	bot.global_position = Vector3(dist, (2.6 if fly else 0.6), 0)
	return bot

func _run() -> void:
	await get_tree().process_frame

	# HUNTER: blade dash engages from mid range.
	var hunter := _spawn("hunter", 12.0, false)
	hunter.set("_dash_cd", 0.5)
	var dashed := false
	for i in 360:
		await get_tree().physics_frame
		if float(hunter.get("_lunge_time")) > 0.3:
			dashed = true
			break
	print("hunter_dash: engaged=%s" % dashed)
	hunter.queue_free()

	# RAPTOR: commits a strafing run, then ends it (cooldown re-armed).
	var raptor := _spawn("raptor", 16.0, true)
	raptor.set("_run_cd", 0.5)
	var ran := false
	var ended := false
	for i in 600:
		await get_tree().physics_frame
		if float(raptor.get("_run_t")) > 0.0:
			ran = true
		elif ran:
			ended = true
			break
	print("raptor_run: committed=%s ended=%s" % [ran, ended])
	raptor.queue_free()

	# RIPPER: spin-up gate first, then the full saw.
	var ripper := _spawn("ripper", 8.0, false)
	var spun := false
	var sawed := false
	for i in 480:
		await get_tree().physics_frame
		if bool(ripper.get("_spinning")):
			spun = true
		if spun and int(ripper.get("_burst_remaining")) >= 10:
			sawed = true
			break
	print("ripper_saw: spinup=%s saw=%s" % [spun, sawed])
	ripper.queue_free()

	# SENTINEL: first volley forced to a mortar salvo -> real shells in the air.
	var sentinel := _spawn("sentinel", 16.0, false)
	sentinel.set("bomb_every", 1)
	var shells := 0
	for i in 600:
		await get_tree().physics_frame
		var found := get_tree().current_scene.find_children("*", "EnemyBomb", true, false)
		shells = maxi(shells, found.size())
		if shells >= 2:
			break
	print("sentinel_salvo: peak_shells=%d" % shells)
	sentinel.queue_free()

	# WARBOT: FURIOUS below 45% + cross-fire hurts the player proxy.
	var warbot := _spawn("warbot", 8.0, false)
	await get_tree().physics_frame
	var whp = warbot.get("hp")
	whp.current_health = whp.max_health * 0.4
	var hp_before: float = _php.get("current_health")
	var furious := false
	for i in 480:
		await get_tree().physics_frame
		if bool(warbot.get("_furious")):
			furious = true
		if furious and float(_php.get("current_health")) < hp_before:
			break
	print("warbot: furious=%s crossfire_dmg=%.0f arms=%d" % [
		furious, hp_before - float(_php.get("current_health")), (warbot.get("_arms") as Array).size()])

	print("UNIQUE_ENEMY_PROBE_DONE")
	get_tree().quit()
