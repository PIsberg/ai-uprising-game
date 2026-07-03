extends Node
## Headless check of dash phase-through: during the dash's i-frame window the
## player's collision mask drops the enemy layer (bit 4) so a dodge can pass
## THROUGH a body-blocking brute, and both mask and vulnerability restore
## cleanly when the dash ends.
##   godot --headless --path . --audio-driver Dummy res://tests/dash_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var lvl := (load("res://scenes/levels/level_01.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(lvl)
	await get_tree().create_timer(2.0).timeout
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	var fails := 0
	if player.collision_mask != 5:
		print("FAIL: resting mask %d != 5 (world+enemy)" % player.collision_mask)
		fails += 1
	Input.action_press("dash")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("dash")
	var mid_mask: int = player.collision_mask
	var mid_invuln: bool = player.get("hp").invulnerable
	print("mid-dash mask=%d invulnerable=%s" % [mid_mask, mid_invuln])
	if mid_mask & 4 != 0:
		print("FAIL: enemy bit still set mid-dash")
		fails += 1
	if not mid_invuln:
		print("FAIL: no i-frames mid-dash")
		fails += 1
	# Wait out the dash and confirm everything restores.
	await get_tree().create_timer(float(player.get("dash_duration")) + 0.3).timeout
	print("post-dash mask=%d invulnerable=%s" % [player.collision_mask, player.get("hp").invulnerable])
	if player.collision_mask != 5:
		print("FAIL: mask not restored after dash")
		fails += 1
	if player.get("hp").invulnerable:
		print("FAIL: i-frames stuck on after dash")
		fails += 1
	# Supply magnetism: a health pack dropped 2.5 m away drifts in and collects
	# on its own while the player stands still (hurt first so it's not refused).
	var d = player.get_node("Damageable")
	d.current_health = d.max_health - 40.0
	d.invulnerable = true # yard enemies must not skew the heal check
	var pack := (load("res://scenes/pickups/health_pack.tscn") as PackedScene).instantiate()
	get_tree().current_scene.add_child(pack)
	(pack as Node3D).global_position = player.global_position + Vector3(2.5, 0.5, 0)
	await get_tree().create_timer(2.0).timeout
	var collected := not is_instance_valid(pack)
	var healed: bool = d.current_health > d.max_health - 40.0
	print("magnet: collected=%s healed=%s hp=%.0f/%.0f" % [collected, healed, d.current_health, d.max_health])
	if not collected or not healed:
		print("FAIL: health pack did not magnet-collect")
		fails += 1
	print("RESULT ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(fails)
