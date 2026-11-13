extends Node3D
## Full-campaign live smoke test. Boots every campaign level scene (real player,
## real enemies, real builder), lets it build + bake the navmesh, then runs a few
## seconds of live simulation and reports health signals per level:
##   - builds ok (scene _ready ran)
##   - player present + alive
##   - navmesh baked (poly count > 0)
##   - enemy count
##   - engagement: did enemies close on the player / fire shots within the window?
## A missing player or navmesh is a problem and fails the run. Robots that
## neither move nor fire are reported as QUIET with the distance the nearest one
## started at, and are not a problem: a robot stands idle until it sees the
## player, and the player here never leaves the spawn. Counting it as one put 11
## levels in red on main, 8 of them with no robot inside the 30 m sight range
## and the rest with a wall in between (#549).
## Every level scene on disk (LevelIds): the list kept here by hand had 24 and
## left out horde and range.
## The player stays put (no input) but is made invulnerable so the sim runs clean.
##   godot --headless --path . --audio-driver Dummy res://tests/campaign_smoke.tscn

const LevelIds := preload("res://tests/level_ids.gd")

func _ready() -> void:
	var problems := 0
	var levels := 0
	for id: String in LevelIds.all():
		problems += await _run_level(id)
		levels += 1
	print("CAMPAIGN_SMOKE_DONE levels=%d problems=%d" % [levels, problems])
	var ok := problems == 0 and levels >= 20
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

func _run_level(id: String) -> int:
	var path := "res://scenes/levels/level_%s.tscn" % id
	if not ResourceLoader.exists(path):
		print("SKIP %-12s (no scene)" % id)
		return 0
	var lvl: Node = (load(path) as PackedScene).instantiate()
	add_child(lvl)
	# build geometry + bake navmesh
	await get_tree().create_timer(2.4).timeout

	var problems := 0
	var notes: Array[String] = []

	# Player present + alive
	var player: Node = lvl.find_child("Player", true, false)
	var pdmg: Damageable = null
	if player:
		pdmg = player.find_child("Damageable", true, false)
		if pdmg:
			pdmg.invulnerable = true
	else:
		notes.append("NO-PLAYER"); problems += 1

	# Navmesh: probe a real path from spawn to a nearby point (poly count via map query)
	var map := get_world_3d().get_navigation_map()
	var def: Dictionary = LevelDefs.get_def(id)
	var spawn: Vector3 = def.get("spawn", (player as Node3D).global_position if player else Vector3.ZERO)
	var probe := spawn + Vector3(6, 0, 6)
	var np := NavigationServer3D.map_get_path(map, spawn, probe, true)
	var polys := np.size()
	if polys < 2:
		notes.append("NO-NAVMESH"); problems += 1

	# Enemy census
	var enemies := get_tree().get_nodes_in_group("enemy")
	var enemy_ct := enemies.size()

	# Run live sim, sample engagement
	var start_dist := _closest_enemy_dist(player, enemies)
	var shots_seen := 0
	var min_dist := start_dist
	var t := 0.0
	while t < 3.2:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		shots_seen = maxi(shots_seen, _count_projectiles(lvl))
		min_dist = minf(min_dist, _closest_enemy_dist(player, enemies))

	var closed := start_dist - min_dist  # positive => enemies advanced
	var engaged := shots_seen > 0 or closed > 1.0
	if enemy_ct > 0 and not engaged:
		notes.append("QUIET(nearest robot starts %.1f m off)" % start_dist)

	var verdict := "OK" if problems == 0 else "PROB"
	print("SMOKE %-12s %-4s enemies=%2d navpoly=%3d shots=%d closed=%.1f %s" % [
		id, verdict, enemy_ct, polys, shots_seen, closed, " ".join(notes)])

	LevelIds.unload(lvl)
	for p in get_children():
		if p is Projectile:
			p.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return problems

func _closest_enemy_dist(player: Node, enemies: Array) -> float:
	if player == null or not (player is Node3D):
		return 999.0
	var pp: Vector3 = (player as Node3D).global_position
	var best := 999.0
	for e in enemies:
		if is_instance_valid(e) and e is Node3D:
			best = minf(best, pp.distance_to((e as Node3D).global_position))
	return best

func _count_projectiles(root: Node) -> int:
	var n := 0
	for c in root.get_children():
		if c is Projectile:
			n += 1
	# projectiles often parent to the level root or tree root; sweep both
	for c in get_children():
		if c is Projectile:
			n += 1
	return n
