extends Node3D
## Breakable cover (scripts/systems/breakable_cover.gd).
## (1) census: how many authored `walls` per level qualify, and every one the
##     builder turns into a BreakableCover in a live level;
## (2) damage: player fire cracks it in two stages without counting as a hit on a
##     robot (accuracy and the AI Director stay clean); a plain enemy round does
##     x0.3, a splash x1.6;
## (3) shatter: the block is freed, rubble is left, shrapnel hurts a body standing
##     beside it, and the level rebakes its navmesh so the footprint becomes
##     walkable floor;
## (4) a shockwave ring (boss slam primitive) damages cover inside its radius.
##   godot --headless --path . --audio-driver Dummy res://tests/breakable_cover_probe.tscn

const LEVEL := "neon" ## a level with several qualifying blocks and no lava

var _fails: Array[String] = []

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	_census()
	await _live()
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _census() -> void:
	print("census (breakable / walls):")
	var total := 0
	var levels := 0
	var reasons := {}
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		var n := 0
		for w in def.get("walls", []):
			var why := BreakableCover.why_not(w, def)
			if why == "":
				n += 1
			else:
				reasons[why] = int(reasons.get(why, 0)) + 1
		print("  %-14s %2d / %d" % [id, n, def.get("walls", []).size()])
		total += n
		levels += 1 if n > 0 else 0
	print("  total %d breakable blocks on %d levels; solid because: %s" % [total, levels, reasons])
	_check(total >= 30 and levels >= 8, "breakable cover is spread across the campaign (%d blocks, %d levels)" % [total, levels])
	# The opt-outs work.
	var w := {"pos": Vector3(0, 1, 0), "size": Vector3(2, 2, 2)}
	_check(BreakableCover.qualifies(w, {}), "a 2 m floor block qualifies")
	_check(not BreakableCover.qualifies(w, {"breakable_cover": false}), "def opt-out keeps it solid")
	_check(not BreakableCover.qualifies({"pos": w["pos"], "size": w["size"], "solid": true}, {}), "per-wall solid keeps it solid")
	_check(not BreakableCover.qualifies(w, {"lights": [{"pos": Vector3(0.5, 2.4, 0)}]}), "a light standing on it keeps it solid")
	_check(not BreakableCover.qualifies(w, {"ramps": [{"pos": Vector3(1.8, 1, 0), "size": Vector3(2, 0.3, 2)}]}), "a ramp leaning on it keeps it solid")
	_check(not BreakableCover.qualifies({"pos": Vector3(0, 2.5, 0), "size": Vector3(2, 2, 2)}, {}), "a block off the floor stays solid")
	_check(not BreakableCover.qualifies({"pos": Vector3(0, 3, 0), "size": Vector3(2, 6, 2)}, {}), "a full-height pillar stays solid")

func _live() -> void:
	print("live level %s:" % LEVEL)
	var def: Dictionary = LevelDefs.get_def(LEVEL)
	var expect := 0
	for w in def.get("walls", []):
		if BreakableCover.qualifies(w, def):
			expect += 1
	var level := (load("res://scenes/levels/level_%s.tscn" % LEVEL) as PackedScene).instantiate() as Node3D
	add_child(level)
	var map := level.get_world_3d().navigation_map
	var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
	for i in 40:
		await _frames(6)
		if NavigationServer3D.map_get_closest_point(map, spawn) != Vector3.ZERO:
			break
	await _frames(10)
	var covers := get_tree().get_nodes_in_group("breakable_cover")
	_check(covers.size() == expect, "builder made every qualifying wall breakable (%d of %d)" % [covers.size(), expect])
	_check(covers.size() >= 2, "the test level has two blocks to break")
	if covers.size() < 2:
		return
	# Freeze the level's robots out of the way: this probe drives damage by hand.
	for e in get_tree().get_nodes_in_group("enemy"):
		e.process_mode = Node.PROCESS_MODE_DISABLED
		(e as Node3D).global_position += Vector3(0, -200, 0)
	var builder := get_tree().get_first_node_in_group("level_builder")
	var player := get_tree().get_first_node_in_group("player")
	_check(builder != null and player != null, "level has a builder and a player")
	if builder == null or player == null:
		return
	player.process_mode = Node.PROCESS_MODE_DISABLED

	var bc: BreakableCover = covers[0]
	var hpmax: float = bc.hp.max_health
	var at: Vector3 = bc.global_position
	# Robots route across the block's footprint: a path between points just past
	# opposite faces must detour while it stands and run straight once it is gone.
	var cross_before := _cross(map, at, bc.size)
	_check(cross_before > 1.25, "intact: a path across the block detours (x%.2f the straight line)" % cross_before)

	# Plain damage scaling.
	var enemy_src := _dummy_enemy(at + Vector3(0, 0, 30))
	var h0: float = bc.hp.current_health
	bc.hp.apply_damage(100.0, enemy_src)
	_check(is_equal_approx(h0 - bc.hp.current_health, 100.0 * BreakableCover.ENEMY_MULT), "enemy round x%.1f (%.1f)" % [BreakableCover.ENEMY_MULT, h0 - bc.hp.current_health])
	h0 = bc.hp.current_health
	bc.hp.apply_damage(10.0, player, false, at)
	_check(is_equal_approx(h0 - bc.hp.current_health, 10.0 * BreakableCover.SPLASH_MULT), "splash x%.1f" % BreakableCover.SPLASH_MULT)

	# Player fire: cracks in stages, never counts as a hit on a robot.
	var hits0 := GameState.stat_hits
	var dir_hits0: int = AIDirector._hits
	bc.hp.apply_damage(bc.hp.current_health - hpmax * 0.6, player)
	_check(bc.stage == 1, "below 66%% HP it cracks (stage %d)" % bc.stage)
	bc.hp.apply_damage(bc.hp.current_health - hpmax * 0.3, player)
	_check(bc.stage == 2, "below 33%% HP it fails (stage %d)" % bc.stage)
	_check(GameState.stat_hits == hits0 and AIDirector._hits == dir_hits0, "chipping cover is not a hit on a robot")

	# Shatter with a body beside it.
	var victim := _dummy_enemy(at + Vector3(bc.size.x * 0.5 + 0.8, 0, 0))
	var vhp: Damageable = victim.get_node("Damageable")
	await _frames(2) # a body moved this frame is not in the broadphase until the next step
	var rebakes0: int = builder.nav_rebakes
	var bc_size: Vector3 = bc.size
	bc.hp.apply_damage(99999.0, player)
	await _frames(2)
	_check(not is_instance_valid(bc), "the block is gone")
	_check(get_tree().get_nodes_in_group("cover_rubble").size() >= 1, "rubble left where it stood")
	_check(vhp.current_health < vhp.max_health, "shrapnel hurt the body beside it (%.0f HP lost)" % (vhp.max_health - vhp.current_health))
	var cross_after := cross_before
	for i in 60:
		await _frames(6)
		cross_after = _cross(map, at, bc_size)
		if cross_after < 1.1:
			break
	_check(builder.nav_rebakes == rebakes0 + 1, "one nav rebake for the break (%d)" % (builder.nav_rebakes - rebakes0))
	_check(cross_after < 1.1, "after the rebake robots path straight through the gap (x%.2f)" % cross_after)
	# Report only: what starting a threaded rebake costs the main thread (geometry parse).
	var t0 := Time.get_ticks_usec()
	builder._rebake_nav()
	print("  rebake main-thread cost %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))

	# A slam ring damages the next block.
	var bc2: BreakableCover = null
	for c in get_tree().get_nodes_in_group("breakable_cover"):
		if is_instance_valid(c) and not (c as BreakableCover)._dead:
			bc2 = c
			break
	if bc2 == null:
		_check(false, "a second block for the slam test")
		return
	var slammer: EnemyBase = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	slammer.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(slammer)
	slammer.global_position = bc2.global_position + Vector3(0, 0, 40)
	var s0: float = bc2.hp.current_health
	slammer.spawn_shockwave_ring(3.0, Color.ORANGE, bc2.global_position)
	_check(bc2.hp.current_health < s0, "a shockwave ring damages cover inside it (%.0f)" % (s0 - bc2.hp.current_health))

## Navmesh path length between points 1.5 m past the block's -X and +X faces,
## at floor height, as a multiple of the straight distance between them.
func _cross(map: RID, at: Vector3, size: Vector3) -> float:
	var off := Vector3(size.x * 0.5 + 1.5, 0, 0)
	var y := at.y - size.y * 0.5
	var a := NavigationServer3D.map_get_closest_point(map, Vector3(at.x, y, at.z) - off)
	var b := NavigationServer3D.map_get_closest_point(map, Vector3(at.x, y, at.z) + off)
	var path := NavigationServer3D.map_get_path(map, a, b, true)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	if path.is_empty() or path[path.size() - 1].distance_to(b) > 0.5:
		return 99.0 # no route at all counts as blocked
	return length / maxf(a.distance_to(b), 0.01)

## A bare body on the enemy layer with health, standing in for a robot.
func _dummy_enemy(pos: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 4
	b.add_to_group("enemy")
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	cs.shape = sh
	cs.position.y = 1.0
	b.add_child(cs)
	var d := Damageable.new()
	d.name = "Damageable"
	d.max_health = 100.0
	b.add_child(d)
	add_child(b)
	b.global_position = pos
	return b
