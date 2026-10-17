extends RefCounted
## Walks the REAL player up a ramp (#290), shared by tests/ramp_walk_triage
## (report over every ramp) and tests/house_stairs_probe (suite). The player
## starts 0.3 m before the foot facing the top, walks (no sprint, no jump),
## re-aims at the top every physics tick, and has 2x the walk time plus 2 s to
## arrive within ARRIVE_XZ of the top at no less than ARRIVE_DY below it.
## Robots are freed every tick, so a late spawn (a boss entrance, a wave)
## cannot shove the walker. Physics time only.

const ARRIVE_XZ := 0.8
const ARRIVE_DY := 0.35

## {ok, at: Vector3 where it ended, best_y: highest point reached}.
static func walk(player: CharacterBody3D, from: Vector3, to: Vector3) -> Dictionary:
	var tree := player.get_tree()
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
			e.queue_free()
		await tree.physics_frame
		t += player.get_physics_process_delta_time()
		best_y = maxf(best_y, player.global_position.y)
		var p := player.global_position
		if Vector2(p.x - to.x, p.z - to.z).length() < ARRIVE_XZ and p.y > to.y - ARRIVE_DY:
			ok = true
			break
	Input.action_release("move_forward")
	return {"ok": ok, "at": player.global_position, "best_y": best_y}
