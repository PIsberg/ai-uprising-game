extends Node3D
## Per-chassis CPU cost (report-only instrument). For every entry in
## LevelBuilder.ENEMY_SCENES: spawn COUNT copies on a flat navmesh floor around
## a real player, wake them all (target + CHASE), and sample the main-thread
## physics time per tick for a moment (tests/tick_clock.gd). Reports the median
## tick and microseconds per robot per tick above the empty-rig baseline, sorted,
## so the chassis whose _physics_process is out of line stands out. Until
## 2026-10-08 it took the median of Performance.TIME_PHYSICS_PROCESS, the worst
## tick of the last second, and so put ~1 ms per robot on a ~0.08 ms cost (#89).
## Bosses are included but spawn fewer copies. RESULT PASS always.
## Restrict with -- types=android,drone. Findings so far live in docs/PERF_NOTES.md.
##   godot --headless --path . --audio-driver Dummy res://tests/enemy_cost_probe.tscn

const COUNT := 8
const BOSS_COUNT := 2
const SAMPLE := 1.5
const BOSSES := ["archon", "colossus", "manus", "overseer", "smasher", "titan", "terminator"]
const TickClock := preload("res://tests/tick_clock.gd")

var _player: Node3D
var _clock

func _ready() -> void:
	_run.call_deferred()

func _build_floor() -> void:
	var region := NavigationRegion3D.new()
	add_child(region)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	mi.mesh = pm
	region.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	region.add_child(body)
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	region.navigation_mesh = nm
	region.bake_navigation_mesh()

## Median physics tick over `seconds`: what a typical tick pays; the mean is
## dragged by spikes (a stream synthesized on first use, an instantiation).
var _base_pairs := 0
var _base_active := 0
var _base_islands := 0

func _sample_physics_ms(seconds: float) -> float:
	_clock.reset()
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
	return _clock.percentile(0.5)

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_clock = TickClock.attach(self)
	_build_floor()
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3.ZERO
	_player.set_physics_process(false)
	await get_tree().physics_frame
	var hp: Node = _player.get_node_or_null("Damageable")
	if hp:
		hp.invulnerable = true
	for i in 30:
		await get_tree().physics_frame
	var baseline := await _sample_physics_ms(0.6)
	_base_pairs = int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
	_base_active = int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	_base_islands = int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT))

	var rows: Array = []
	var types: Array = LevelBuilder.ENEMY_SCENES.keys()
	types.sort()
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("types="):
			types = Array(String(a).trim_prefix("types=").split(",", false))
	for t in types:
		# ENEMY_SCENES holds paths since the lazy scene tables (#94); this line
		# still indexed it as a PackedScene and the probe hung on a script error.
		var scene: PackedScene = LevelBuilder.enemy_scene(t)
		var count: int = BOSS_COUNT if BOSSES.has(t) else COUNT
		var spawned: Array[Node] = []
		for i in count:
			var e: Node3D = scene.instantiate()
			var ang := TAU * float(i) / float(count)
			add_child(e)
			e.global_position = Vector3(cos(ang), 0.0, sin(ang)) * randf_range(10.0, 18.0) + Vector3.UP * 0.5
			e.rotation = Vector3(0, PI, 0)
			spawned.append(e)
		for i in 20:
			await get_tree().physics_frame
		for e in spawned:
			if is_instance_valid(e) and "target" in e:
				e.set("target", _player)
				if e.has_method("set_state"):
					e.call("set_state", 3) # CHASE
		var ms := await _sample_physics_ms(SAMPLE)
		# Physics-server counters are counts, not times, so they hold still
		# where the tick timing swings 10x between runs.
		var pairs := int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
		var active := int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
		var islands := int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT))
		var alive := 0
		for e in spawned:
			if is_instance_valid(e):
				alive += 1
		var per_us := (ms - baseline) * 1000.0 / maxf(alive, 1)
		rows.append({"type": t, "n": alive, "ms": ms, "per_us": per_us,
			"pairs": pairs, "active": active, "islands": islands})
		for e in spawned:
			if is_instance_valid(e):
				e.queue_free()
		for e in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e):
				e.queue_free()
		for i in 6:
			await get_tree().physics_frame
	rows.sort_custom(func(a, b): return float(a["per_us"]) > float(b["per_us"]))
	print("baseline physics (player + floor): %.2f ms" % baseline)
	print("baseline physics server: pairs=%d active=%d islands=%d" % [_base_pairs, _base_active, _base_islands])
	print("ENEMY_COST  chassis        n   phys ms   us/robot/frame   pairs active islands")
	for r in rows:
		print("ENEMY_COST  %-12s %3d   %6.2f   %8.0f   %5d %6d %7d" % [r["type"], r["n"], r["ms"], r["per_us"], r["pairs"], r["active"], r["islands"]])
	print("ENEMY_COST_DONE")
	print("RESULT PASS")
	get_tree().quit()
