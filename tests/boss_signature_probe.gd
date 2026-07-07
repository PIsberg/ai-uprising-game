extends Node3D
## Verifies the two new boss signatures fire and land:
##  - SMASHER (rusty claws): the CLAW RAKE lunge connects a talon hit.
##  - OVERSEER (gunship): the ROCKET BARRAGE lobs a fan of arcing bombs.

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.0).timeout
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var pdmg = player.get_node("Damageable")

	# ---- SMASHER: claw rake ----
	var sm: Node3D = (load("res://scenes/enemies/smasher.tscn") as PackedScene).instantiate()
	lvl.add_child(sm)
	sm.global_position = Vector3(0, 1.0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	sm._wake = 0.0
	sm.hp.invulnerable = false
	# Put the player right in the rake path, a few metres in front.
	player.global_position = sm.global_position - sm.global_transform.basis.z * 3.2
	player.global_position.y = 1.0
	sm.target = player
	pdmg.current_health = 100.0
	# Side camera to see the claw streaks + the boss lunge.
	var cam := player.find_child("Camera3D", true, false) as Camera3D
	if cam:
		cam.current = true
		cam.global_position = sm.global_position + Vector3(9, 5, 2)
		cam.look_at(sm.global_position + Vector3(0, 4, -2), Vector3.UP)
	sm._begin_rake()
	var before: float = pdmg.current_health
	for i in range(30): # into the lunge, streaks live
		await get_tree().physics_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/boss_rake.png")
	for i in range(40):
		await get_tree().physics_frame
	print("SMASHER claw rake: player hp %.0f -> %.0f (rake_hit=%s)" % [before, pdmg.current_health, sm._rake_hit])

	# ---- OVERSEER: rocket barrage ----
	pdmg.invulnerable = true # not testing damage here, just the salvo
	var ov: Node3D = (load("res://scenes/enemies/overseer.tscn") as PackedScene).instantiate()
	lvl.add_child(ov)
	ov.global_position = Vector3(12, 6.0, 12)
	await get_tree().physics_frame
	ov.target = player
	var bombs_before := get_tree().root.find_children("*", "EnemyBomb", true, false).size()
	ov._barrage(lvl)
	await get_tree().physics_frame
	var bombs_after := get_tree().root.find_children("*", "EnemyBomb", true, false).size()
	print("OVERSEER barrage: EnemyBombs %d -> %d (fired %d rockets)" % [bombs_before, bombs_after, bombs_after - bombs_before])

	print("BOSS_SIGNATURE_PROBE_DONE")
	get_tree().quit()
