extends Node
## Probe: the REAL player reaches the six pickups the navmesh cannot route to (#498).
## SPOTS below is also read by tests/pickup_reach_sweep (suite): a pickup with
## no navmesh route fails there unless it is listed here, and an entry no pickup
## stands on fails there as stale (#528).
## tests/pickup_reach_sweep flags them "no navmesh route from the spawn", which
## proves nothing: the navmesh follows no lift, jump or grapple. This takes the
## Player along the route each one's def names, in the built level:
##   step     horde, crucible: the ammo on the tower roof's raised pad. From where
##            the navmesh path gives up on the roof, walk onto the pad.
##   jump     gemini: the ammo on the 1 m centre dais. Walk at it and jump.
##   lift     lava_world, water_world: ride the cargo lift from its island to the
##            top deck, walk to the pickup. The path from the spawn must reach the
##            lift's foot.
##   grapple  level 01: the Shotgun on the GRAPPLE PAD (no ramp by design). From
##            the street, fire the tether at the pad's lip and land on top.
## Arrival is the player's feet within REACH_XZ of the pickup on the surface it
## sits on, not the pickup being consumed (a full-health player leaves a medkit).
## Robots are switched off as in tests/ramp_walker.gd. Physics time only.
##   godot --headless --path . --audio-driver Dummy --fixed-fps 60 res://tests/pickup_route_probe.tscn [-- levels=01,gemini]

const REACH_XZ := 1.2

## id -> {at: the pickup (world), route}
const SPOTS := {
	"01": {"at": Vector3(22.4, 6.1, -22.4), "route": "grapple"},
	"gemini": {"at": Vector3(-2.8, 1.0, 0.0), "route": "jump"},
	"horde": {"at": Vector3(0.0, 7.9, -23.8), "route": "step"},
	"crucible": {"at": Vector3(0.0, 7.9, -23.8), "route": "step"},
	"lava_world": {"at": Vector3(9.8, 8.1, -23.2), "route": "lift"},
	"water_world": {"at": Vector3(30.1, 8.1, 9.8), "route": "lift"},
}

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _quiet() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.process_mode != Node.PROCESS_MODE_DISABLED:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			if e is CollisionObject3D:
				(e as CollisionObject3D).collision_layer = 0
			if e is Node3D:
				(e as Node3D).visible = false

func _aim(player: CharacterBody3D, to: Vector3) -> void:
	var d := Vector3(to.x - player.global_position.x, 0, to.z - player.global_position.z)
	if d.length() > 0.05:
		player.rotation.y = atan2(-d.x, -d.z)

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## The surface the pickup floats over (the first world hit straight down).
func _floor_under(world: World3D, at: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, at + Vector3.DOWN * 4.0, 1)
	var hit := world.direct_space_state.intersect_ray(q)
	return hit["position"] if hit else at + Vector3.DOWN * 0.9

## Walk at `to` (jumping whenever grounded if `hop`) until the feet are within
## REACH_XZ of it on a floor no lower than `floor_y - below`, or `budget` s pass.
func _go(player: CharacterBody3D, to: Vector3, floor_y: float, budget: float, hop: bool, below: float = 0.3) -> bool:
	var t := 0.0
	var arrived := false
	Input.action_press("move_forward")
	while t < budget:
		_aim(player, to)
		_quiet()
		if hop:
			if player.is_on_floor():
				Input.action_press("jump")
			else:
				Input.action_release("jump")
		await get_tree().physics_frame
		t += player.get_physics_process_delta_time()
		var p := player.global_position
		if _xz(p, to) < REACH_XZ and p.y > floor_y - below and player.is_on_floor():
			arrived = true
			break
	Input.action_release("move_forward")
	Input.action_release("jump")
	return arrived

func _run() -> void:
	var ids: Array = SPOTS.keys()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("levels="):
			ids = Array(a.substr(7).split(",", false))
	for id: String in ids:
		seed(hash(id))
		var lvl: Node = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
		add_child(lvl)
		var player: CharacterBody3D = null
		for i in 150:
			if player == null:
				player = get_tree().get_first_node_in_group("player") as CharacterBody3D
				if player:
					player.set("_god", true)
					var hp = player.get("hp")
					if hp:
						hp.invulnerable = true
			await get_tree().physics_frame
		if player == null:
			_check("%s builds a player" % id, false)
		else:
			var spot: Dictionary = SPOTS[id]
			await call("_route_%s" % spot["route"], id, player, spot["at"])
		lvl.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

## Where the navmesh path from `from` toward `goal` ends.
func _path_end(player: CharacterBody3D, from: Vector3, goal: Vector3) -> Vector3:
	var map := player.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, from, NavigationServer3D.map_get_closest_point(map, goal), true)
	return path[path.size() - 1] if path.size() > 0 else from

func _route_step(id: String, player: CharacterBody3D, at: Vector3) -> void:
	var surf := _floor_under(player.get_world_3d(), at)
	var end := _path_end(player, player.global_position, at)
	# The path must get onto the roof itself: within a few metres and under 1 m below.
	_check("%s: the navmesh path from the spawn reaches the roof by the pad" % id, _xz(end, at) < 5.0 and end.y > surf.y - 1.0, "(ends %s, pad %s)" % [end, surf])
	player.velocity = Vector3.ZERO
	player.global_position = end + Vector3.UP * 0.1
	# On the pad itself (0.22 m above the roof), not beside it: 0.08 m tolerance.
	_check("%s: the pad is a step up from the roof, not level with it" % id, surf.y - (end.y - 0.35) > 0.1, "(roof %.2f, pad %.2f)" % [end.y - 0.35, surf.y])
	var arrived: bool = await _go(player, at, surf.y, 6.0, false, 0.08)
	_check("%s: a walk from there steps onto the pad and reaches the ammo" % id, arrived, "(at %s, pad top %.2f)" % [player.global_position, surf.y])

func _route_jump(id: String, player: CharacterBody3D, at: Vector3) -> void:
	var surf := _floor_under(player.get_world_3d(), at)
	var end := _path_end(player, player.global_position, at)
	_check("%s: the navmesh path from the spawn reaches the floor by the dais" % id, _xz(end, at) < 9.0, "(ends %s)" % end)
	# First without jumping: is the dais what the navmesh says it is, a step too
	# high to walk? Reported, not asserted: either way the player gets there.
	player.velocity = Vector3.ZERO
	player.global_position = end + Vector3.UP * 0.1
	var walked: bool = await _go(player, at, surf.y, 5.0, false)
	print("     %s: a plain walk %s (ends %s)" % [id, "also gets there" if walked else "stops at the dais", player.global_position])
	player.velocity = Vector3.ZERO
	player.global_position = end + Vector3.UP * 0.1
	var arrived: bool = await _go(player, at, surf.y, 8.0, true)
	_check("%s: walking at the dais and jumping lands on it by the ammo" % id, arrived, "(at %s, dais top %.2f)" % [player.global_position, surf.y])

func _find_lift(n: Node, at: Vector3, best: Array) -> void:
	if n is CargoLift:
		var d := _xz((n as Node3D).global_position, at)
		if best.is_empty() or d < float(best[1]):
			best.clear()
			best.append(n)
			best.append(d)
	for c in n.get_children():
		_find_lift(c, at, best)

func _route_lift(id: String, player: CharacterBody3D, at: Vector3) -> void:
	var best: Array = []
	_find_lift(self, at, best)
	_check("%s has a cargo lift" % id, not best.is_empty())
	if best.is_empty():
		return
	var lift := best[0] as CargoLift
	var foot := lift.global_position
	var surf := _floor_under(player.get_world_3d(), at)
	_check("%s: the lift's top is the pickup's deck" % id, absf(lift.top - surf.y) < 0.3, "(top %.2f, deck %.2f)" % [lift.top, surf.y])
	var end := _path_end(player, player.global_position, foot)
	_check("%s: the navmesh path from the spawn reaches the lift's foot" % id, _xz(end, foot) < 3.5 and absf(end.y - foot.y) < 1.0, "(ends %s, lift %s)" % [end, foot])
	# Call the car if it is not down, then board from beside it, on foot.
	player.velocity = Vector3.ZERO
	player.global_position = end + Vector3.UP * 0.1
	var t := 0.0
	while not lift.at_bottom() and t < 12.0:
		_quiet()
		await get_tree().physics_frame
		t += player.get_physics_process_delta_time()
	_check("%s: the car is at (or comes to) the bottom landing" % id, lift.at_bottom(), "(%.1f s)" % t)
	var aboard: bool = await _go(player, foot, foot.y, 6.0, false)
	_check("%s: the player walks onto the car" % id, aboard, "(at %s)" % player.global_position)
	t = 0.0
	var budget := (lift.top - foot.y) / maxf(lift.speed, 0.1) + lift.board_delay + 4.0
	while not lift.at_top() and t < budget:
		_quiet()
		await get_tree().physics_frame
		t += player.get_physics_process_delta_time()
	_check("%s: the car carries the player to the top" % id, lift.at_top() and player.global_position.y > lift.top - 0.4, "(%.1f s, player y %.2f, top %.2f)" % [t, player.global_position.y, lift.top])
	var arrived: bool = await _go(player, at, surf.y, _xz(player.global_position, at) / 2.5 + 4.0, false)
	_check("%s: a walk along the deck reaches the pickup" % id, arrived, "(at %s)" % player.global_position)

func _route_grapple(id: String, player: CharacterBody3D, at: Vector3) -> void:
	var world := player.get_world_3d()
	var surf := _floor_under(world, at)
	var map := world.navigation_map
	var end := _path_end(player, player.global_position, at)
	_check("%s: the navmesh path from the spawn reaches the street under the pad" % id, _xz(end, at) < 6.0 and end.y < surf.y - 3.0, "(ends %s, pad top %.2f)" % [end, surf.y])
	# Stand on the street 11 m out, square to one of the pad's faces (the first of
	# the four sides the navmesh lets the player stand on).
	var stand := Vector3.ZERO
	var side := Vector3.ZERO
	for d: Vector3 in [Vector3.LEFT, Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD]:
		var want := Vector3(at.x, 0.3, at.z) + d * 11.0
		var snap := NavigationServer3D.map_get_closest_point(map, want)
		var back := _path_end(player, end, snap)
		if _xz(snap, want) < 1.0 and snap.y < 1.0 and _xz(back, snap) < 0.6 and absf(back.y - snap.y) < 0.6:
			stand = snap
			side = d
			break
	_check("%s: and from there to a spot 11 m out, square to the pad" % id, side != Vector3.ZERO, "(stand %s)" % stand)
	if side == Vector3.ZERO:
		return
	player.velocity = Vector3.ZERO
	player.global_position = stand + Vector3.UP * 0.1
	for i in 20:
		_quiet()
		await get_tree().physics_frame
	# The pad's lip on this side: where a level ray 0.15 m under its top meets
	# its face. That is where the def says to fire the tether.
	var y := surf.y - 0.15
	var fq := PhysicsRayQueryParameters3D.create(Vector3(stand.x, y, stand.z), Vector3(at.x, y, at.z), 1)
	fq.exclude = [player.get_rid()]
	var face := world.direct_space_state.intersect_ray(fq)
	_check("%s: the pad has a face on that side" % id, not face.is_empty() and _xz(face.get("position", stand), at) < 5.0, "(%s)" % face.get("position", "nothing"))
	if face.is_empty():
		return
	var lip: Vector3 = face["position"]
	var cam := player.get("camera") as Camera3D
	var eye: Vector3 = cam.global_position if cam else player.global_position + Vector3.UP * 1.6
	_aim(player, lip)
	var head := player.get_node("Head") as Node3D
	head.rotation.x = atan2(lip.y - eye.y, _xz(eye, lip))
	for i in 3:
		await get_tree().physics_frame
	Input.action_press("grapple")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("grapple")
	var attached: bool = player.get("_grappling")
	var anchor: Vector3 = player.get("_grapple_point")
	_check("%s: the tether bites the pad's lip" % id, attached and anchor.distance_to(lip) < 0.5 and eye.distance_to(lip) < float(player.get("grapple_range")), "(anchor %s, lip %s, %.1f m)" % [anchor, lip, eye.distance_to(lip)])
	# Ride the winch holding forward; once it lets go, keep walking at the pickup.
	var landed: bool = await _go(player, at, surf.y, 9.0, false)
	_check("%s: the winch lands the player on the pad at the Shotgun" % id, landed, "(at %s, pad top %.2f)" % [player.global_position, surf.y])
