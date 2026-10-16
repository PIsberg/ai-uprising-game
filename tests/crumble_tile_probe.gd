extends Node3D
## Crumbling slabs (CrumbleTile, def key `crumble_tiles`). Unit pass with a
## stand-in player moved by hand (origin at the feet, like the real player):
##   - untouched, a slab stays solid;
##   - a player landing on it starts the crack: still solid HOLD later minus a
##     margin, gone (a ray falls through) shortly after HOLD;
##   - it does not reform while the player is still in its column, and does
##     once they leave, solid again after GONE + REFORM;
##   - a robot standing on it never cracks it (traps spare robots);
##   - walking up teaches the rule once.
## Campaign pass: on every level with crumble_tiles, every slab sits over a
## hazard bed, the column above it is clear, it is off the navmesh (robots
## never path over), and every hop along the line, from the solid deck at
## `from` across the slabs to the solid deck at `to`, is short enough to jump
## from a walk.
##   godot --headless --path . --audio-driver Dummy res://tests/crumble_tile_probe.tscn

## A walking jump: 5.5 m/s for 2 * 7.5 / 24 s of air is 3.4 m; leave margin.
const MAX_HOP := 2.6

var _fails: Array[String] = []
var _hints: Array[String] = []

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	await _frames(10)
	GameState.teach_hint.connect(func(t: String) -> void: _hints.append(t))
	var prev_state = GameState.current_state
	GameState.current_state = GameState.State.PLAYING
	await _unit()
	GameState.current_state = prev_state
	await _campaign()
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _seconds(s: float) -> void:
	await _frames(int(ceil(s * Engine.physics_ticks_per_second)))

## Is there solid ground at the slab's top under (x, z)?
func _solid(at: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.0, at + Vector3.DOWN * 0.3, 1)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _unit() -> void:
	print("unit:")
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	player.position = Vector3(40, 1.6, 0)
	add_child(player)
	var tile := CrumbleTile.new()
	tile.position = Vector3(0, 1.6, 0)
	add_child(tile)
	await _frames(4)
	var top := tile.global_position

	await _seconds(2.0)
	_check(_solid(top) and tile.phase == CrumbleTile.Phase.SOLID, "untouched, it stays solid")
	_hints.clear()
	player.global_position = top + Vector3(8, 0, 0)
	await _frames(4)
	_check(_hints.size() == 1 and _hints[0] == CrumbleTile.TEACH_TEXT, "walking up teaches the rule (%s)" % [_hints])

	player.global_position = top + Vector3(0.6, 0.0, -0.4)
	await _seconds(CrumbleTile.HOLD - 0.25)
	_check(_solid(top) and tile.phase == CrumbleTile.Phase.CRACKING,
		"landing starts the crack; it holds for now (phase %d)" % tile.phase)
	await _seconds(0.45)
	_check(not _solid(top) and tile.phase == CrumbleTile.Phase.GONE, "then it drops (phase %d)" % tile.phase)

	# The player is still in its column (fell through): no reform on top of them.
	player.global_position = top + Vector3(0.2, -1.5, 0.0)
	await _seconds(CrumbleTile.GONE_TIME + CrumbleTile.REFORM_TIME + 0.5)
	_check(not _solid(top) and tile.phase == CrumbleTile.Phase.GONE,
		"it does not start to reform while the player is in its column (phase %d)" % tile.phase)
	player.global_position = top + Vector3(30, 0, 0)
	await _seconds(CrumbleTile.REFORM_TIME + 0.4)
	_check(_solid(top) and tile.phase == CrumbleTile.Phase.SOLID, "it reforms once the player is clear (phase %d)" % tile.phase)

	# A robot on it: nothing.
	var bot: EnemyBase = LevelBuilder.enemy_scene("android").instantiate()
	bot.position = top + Vector3(0, 0.05, 0)
	bot.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(bot)
	await _seconds(2.0)
	_check(_solid(top) and tile.phase == CrumbleTile.Phase.SOLID, "a robot standing on it never cracks it")
	bot.queue_free()
	tile.queue_free()
	player.queue_free()
	await _frames(4)

func _campaign() -> void:
	var found := 0
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		var lines: Array = def.get("crumble_tiles", [])
		if lines.is_empty():
			continue
		print("level %s:" % id)
		var level := (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate() as Node3D
		add_child(level)
		var map := level.get_world_3d().navigation_map
		var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
		for i in 40:
			await _frames(6)
			if NavigationServer3D.map_get_closest_point(map, spawn) != Vector3.ZERO:
				break
		await _frames(10)
		var tiles := level.find_children("*", "CrumbleTile", true, false)
		var beds := level.find_children("*", "LavaHazard", true, false)
		var space := level.get_world_3d().direct_space_state
		for li in lines.size():
			var line: Dictionary = lines[li]
			var from: Vector3 = line["from"]
			var to: Vector3 = line["to"]
			var mine: Array = []
			for t in tiles:
				if (t as CrumbleTile).line == li:
					mine.append(t)
			found += mine.size()
			_check(mine.size() == int(line.get("count", 0)), "%s line %d builds %d slabs (%d)" % [id, li, int(line.get("count", 0)), mine.size()])
			var dir := (to - from)
			dir.y = 0.0
			dir = dir.normalized()
			# Decks at both ends: solid ground just behind each end point.
			for end in [from - dir * 0.5, to + dir * 0.5]:
				var q := PhysicsRayQueryParameters3D.create(end + Vector3.UP * 1.0, end + Vector3.DOWN * 0.4, 1)
				_check(not space.intersect_ray(q).is_empty(), "%s line %d has a deck at %s" % [id, li, end])
			var prev_edge := from
			for t in mine:
				var ct := (t as CrumbleTile).global_position
				var half := (t as CrumbleTile).size * 0.5
				var over_bed := false
				for b in beds:
					var lb := b as LavaHazard
					var local := lb.global_transform.affine_inverse() * ct
					if absf(local.x) <= lb.size.x * 0.5 and absf(local.z) <= lb.size.y * 0.5:
						over_bed = true
				_check(over_bed, "%s slab at %s is over a hazard bed" % [id, ct])
				var hop := Vector2(ct.x - prev_edge.x, ct.z - prev_edge.z).length() - half
				_check(hop <= MAX_HOP, "%s hop onto the slab at %s is %.2f m (<= %.1f)" % [id, ct, hop, MAX_HOP])
				prev_edge = ct + dir * half
				var near := NavigationServer3D.map_get_closest_point(map, ct)
				_check(Vector2(near.x - ct.x, near.z - ct.z).length() > half,
					"%s slab at %s is off the navmesh (nearest %.1f m)" % [id, ct, Vector2(near.x - ct.x, near.z - ct.z).length()])
				var box := BoxShape3D.new()
				box.size = Vector3(half * 2.0 - 0.2, 2.0, half * 2.0 - 0.2)
				var sq := PhysicsShapeQueryParameters3D.new()
				sq.shape = box
				sq.transform = Transform3D(Basis(), ct + Vector3.UP * 1.1)
				sq.collision_mask = 1
				_check(space.intersect_shape(sq, 1).is_empty(), "%s column over the slab at %s is clear" % [id, ct])
			var last_hop := Vector2(to.x - prev_edge.x, to.z - prev_edge.z).length()
			_check(last_hop <= MAX_HOP, "%s last hop onto the deck at %s is %.2f m" % [id, to, last_hop])
		level.queue_free()
		await _frames(4)
	_check(found >= 1, "at least one campaign level authors crumble tiles (%d slabs)" % found)
