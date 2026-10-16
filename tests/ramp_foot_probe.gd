extends Node3D
## Ramp feet robots can climb (LevelBuilder._build_ramp_wedge). Robots have no
## step-up assist (the player does), so a ramp whose foot tapers to a point
## leaves 0.3-0.5 m vertical side faces at ground level that stop any robot
## approaching off the centre line. Measured on the Suburb canal bridge: an
## android pinned at the west approach for 20+ s, 1-2 m either side of the tip.
## Builds ramps with the real builder function on a flat baked navmesh:
##   - a GROUND-foot ramp is walkable across its width from the foot up: at
##     1 m along the climb, 1.5 m off the centre line, the surface is there;
##   - a real android walking to the deck from 1.6 m off the centre line climbs
##     it (escort walk = EnemyBase._move_toward, the path every robot uses);
##   - an ELEVATED-foot ramp (a tower corner, a sky-bridge) still tapers, so a
##     departing ramp never overhangs the arriving one below it.
##   godot --headless --path . --audio-driver Dummy res://tests/ramp_foot_probe.tscn

const RUN := 8.0
const RISE := 2.0
const WIDTH := 4.0

var _fails: Array[String] = []

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	await _frames(10)
	var prev_state = GameState.current_state
	GameState.current_state = GameState.State.PLAYING
	await _run()
	GameState.current_state = prev_state
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## Build a ramp with the builder's own function and move its body under `into`.
func _ramp(into: Node, from: Vector3, to: Vector3) -> void:
	var lb := LevelBuilder.new()
	lb._build_ramp_wedge(from, to, WIDTH, 0.5, "ProbeRamp")
	for c in lb.get_children():
		lb.remove_child(c)
		into.add_child(c)
	lb.free()

func _box(into: Node, center: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = center
	into.add_child(sb)

## Height of the first surface straight down at (x, z), or -INF for none.
func _top(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 6.0, z), Vector3(x, -1.0, z), 1)
	var h := get_world_3d().direct_space_state.intersect_ray(q)
	return h.position.y if h else -INF

func _run() -> void:
	var nav := NavigationRegion3D.new()
	add_child(nav)
	_box(nav, Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	# Ground-foot ramp along +x onto a deck; an elevated one well clear of it.
	_ramp(nav, Vector3(0, 0, 0), Vector3(RUN, RISE, 0))
	_box(nav, Vector3(RUN + 3.0, RISE - 0.2, 0), Vector3(6, 0.4, WIDTH))
	_box(nav, Vector3(-14, 1.8, 16), Vector3(8, 0.4, 8)) # the landing behind the elevated foot
	_ramp(nav, Vector3(-10, 2.0, 16), Vector3(-10 + RUN, 2.0 + RISE, 16))
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.agent_radius = 0.5
	nm.agent_max_climb = 0.35
	nm.cell_size = 0.25
	nm.cell_height = 0.1
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh(false)
	await _frames(20)

	var line_y := RISE / RUN * 1.0
	for side in [-1.5, 1.5]:
		var y := _top(1.0, side)
		_check(absf(y - line_y) < 0.12,
			"ground foot: surface 1 m up the climb, %.1f m off centre (top %.2f, line %.2f)" % [side, y, line_y])
	var ey := _top(-10 + 1.0, 16 + 1.5)
	_check(ey < 2.0 + RISE / RUN - 0.12,
		"elevated foot still tapers: no deck 1 m up, 1.5 m off centre (top %.2f)" % ey)

	# A real android walks from beside the foot to the deck.
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	player.position = Vector3(30, 0.05, -30)
	add_child(player)
	for off in [-1.6, 1.6]:
		var u: EnemyBase = LevelBuilder.enemy_scene("android").instantiate()
		u.position = Vector3(-4.0, 0.3, off)
		nav.add_child(u)
		await _frames(4)
		u.hijack(3600.0, player)
		u.escort_goal = Vector3(RUN + 3.0, RISE, 0.0)
		u.escort_go = true
		var climbed := false
		for i in 40: # 10 s
			await _frames(15)
			if u.global_position.y > RISE - 0.3 and u.global_position.x > RUN:
				climbed = true
				break
		_check(climbed, "an android approaching %.1f m off centre climbs onto the deck (at %s)" % [off, u.global_position])
		u.queue_free()
		await _frames(2)
	player.queue_free()
	nav.queue_free()
