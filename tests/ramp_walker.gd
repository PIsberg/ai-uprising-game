extends RefCounted
## Walks the REAL player up a ramp (#290), shared by tests/ramp_walk_triage
## (report over every ramp) and tests/house_stairs_probe (suite). The player
## starts 0.3 m before the foot facing the top, walks (no sprint, no jump),
## re-aims at the top every physics tick, and has 2x the walk time plus 2 s to
## arrive within ARRIVE_XZ of the top at no less than ARRIVE_DY below it.
## Every robot is switched off each tick (no processing, no collision, hidden),
## so a late spawn (a boss entrance, a wave) cannot shove the walker. Not freed:
## clearing a level's robots completes its kill-all objective, which ends play
## and froze the player on every ramp of horde, frostbreak and desert.
## Physics time only.

const ARRIVE_XZ := 0.8
const ARRIVE_DY := 0.35

## {ok, at: Vector3 where it ended, best_y: highest point reached}.
static func walk(player: CharacterBody3D, from: Vector3, to: Vector3) -> Dictionary:
	var tree := player.get_tree()
	# A ramp that ends in a zipline station (level 01's and titan's SkyBridge)
	# leaves the player riding the cable, which then holds them through every
	# later walk: let go first.
	if player.get("_grappling") and player.has_method("_end_grapple"):
		player.call("_end_grapple")
	var flat := Vector3(to.x - from.x, 0, to.z - from.z)
	var dir := flat.normalized()
	player.velocity = Vector3.ZERO
	player.global_position = from - dir * 0.3 + Vector3.UP * 0.15
	var walk_speed: float = float(player.get("walk_speed")) if player.get("walk_speed") != null else 5.0
	var budget := flat.length() / maxf(walk_speed, 0.5) * 2.0 + 2.0
	var t := 0.0
	var best_y := player.global_position.y
	var ok := false
	Input.action_press("move_forward")
	while t < budget:
		var to_top := Vector3(to.x - player.global_position.x, 0, to.z - player.global_position.z)
		if to_top.length() > 0.05:
			player.rotation.y = atan2(-to_top.x, -to_top.z)
		for e in tree.get_nodes_in_group("enemies"):
			if e.process_mode != Node.PROCESS_MODE_DISABLED:
				e.process_mode = Node.PROCESS_MODE_DISABLED
				if e is CollisionObject3D:
					(e as CollisionObject3D).collision_layer = 0
				if e is Node3D:
					(e as Node3D).visible = false
		await tree.physics_frame
		t += player.get_physics_process_delta_time()
		best_y = maxf(best_y, player.global_position.y)
		var p := player.global_position
		if Vector2(p.x - to.x, p.z - to.z).length() < ARRIVE_XZ and p.y > to.y - ARRIVE_DY:
			ok = true
			break
	var why := _state(player)
	Input.action_release("move_forward")
	return {"ok": ok, "at": player.global_position, "best_y": best_y, "state": why}

## What could be holding the player when a walk ends: anything here other than
## an on-floor walk is the harness or a game system, not the ramp.
static func _state(player: CharacterBody3D) -> String:
	var out: Array[String] = []
	if player.get_tree().paused:
		out.append("tree paused")
	if not player.can_process():
		out.append("player not processing")
	for k in ["_dead", "_sliding", "_wall_running", "_grappling"]:
		if player.get(k):
			out.append(k)
	for k in ["_dash_time", "_launch_t"]:
		if float(player.get(k) if player.get(k) != null else 0.0) > 0.0:
			out.append(k)
	if not Input.is_action_pressed("move_forward"):
		out.append("move_forward not pressed")
	out.append("v %.2f floor %s gs %s ts %.2f" % [player.velocity.length(), player.is_on_floor(), str(GameState.current_state), Engine.time_scale])
	return ", ".join(out)
