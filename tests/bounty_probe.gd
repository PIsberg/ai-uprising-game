extends Node3D
## Verifies the BOUNTY director: a live enemy gets tagged (flag + beacon marker),
## killing it awards the bonus + clears the director, and a bounty always drops
## the rare prize.

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.5).timeout # let the spawner populate the arena
	GameState.current_state = GameState.State.PLAYING

	var enemies := get_tree().get_nodes_in_group("enemy")
	print("live enemies: %d" % enemies.size())

	# Force a mark now (bypass the 24s cadence).
	var marked := [""]
	GameState.bounty_marked.connect(func(l: String): marked[0] = l)
	GameState._try_mark_bounty()
	await get_tree().process_frame
	var marked_label: String = marked[0]

	var bounty: EnemyBase = null
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and e.is_bounty:
			bounty = e
			break
	print("bounty marked: %s (label='%s') marker=%s" % [
		bounty != null, marked_label, bounty != null and bounty._bounty_marker != null])

	# Screenshot the beacon.
	if bounty:
		var cam := get_viewport().get_camera_3d()
		if cam:
			cam.look_at(bounty.global_position + Vector3.UP * 1.5, Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/bounty.png")

	# Claim it: lethal hit -> _on_died -> claim_bounty (+300, director clears).
	var score_before := GameState.score
	var claimed := [-1]
	GameState.bounty_claimed.connect(func(p: int): claimed[0] = p)
	var pickups_before := get_tree().get_nodes_in_group("pickup").size()
	if bounty and bounty.hp:
		print("pre-kill: is_bounty=%s alive=%s score_value=%d state=%d elite='%s'" % [
			bounty.is_bounty, bounty.hp.is_alive(), bounty.score_value, bounty.state, bounty.elite])
		bounty.hp.current_health = 5.0
		bounty.hp.apply_damage(999.0, self)
		print("post-hit: alive=%s is_bounty=%s" % [bounty.hp.is_alive(), bounty.is_bounty])
	await get_tree().create_timer(0.3).timeout
	var claimed_pts: int = claimed[0]
	var pickups_after := get_tree().get_nodes_in_group("pickup").size()
	print("after kill: score +%d (claim signal=%d) director_cleared=%s prize_dropped=%s" % [
		GameState.score - score_before, claimed_pts,
		GameState._bounty == null, pickups_after > pickups_before])
	print("BOUNTY_PROBE_DONE")
	get_tree().quit()
