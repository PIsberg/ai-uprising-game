extends Node3D
## Per-chassis CPU cost (report-only instrument). For every entry in
## LevelBuilder.ENEMY_SCENES: spawn COUNT copies on a flat navmesh floor around
## a real player, wake them all (target + CHASE), and sample the main-thread
## physics time for a moment. Reports microseconds per robot per physics frame,
## sorted, so the chassis whose _physics_process is out of line stands out.
## Bosses are included but spawn fewer copies. RESULT PASS always.
## Restrict with -- types=android,drone. Findings so far live in docs/PERF_NOTES.md.
##   godot --headless --path . --audio-driver Dummy res://tests/enemy_cost_probe.tscn

const COUNT := 8
const BOSS_COUNT := 2
const SAMPLE := 1.5
const BOSSES := ["archon", "colossus", "manus", "overseer", "smasher", "titan", "terminator"]

var _player: Node3D

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

## Median of the per-frame physics-tick time over `seconds`: TIME_PHYSICS_PROCESS
## reports the last physics tick (calibrated: a 2 ms busy-wait reads 2.07 ms),
## and the median is what a typical tick pays; the mean is dragged by spikes.
func _sample_physics_ms(seconds: float) -> float:
	var s: Array[float] = []
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		s.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	s.sort()
	return s[s.size() / 2] if s.size() > 0 else 0.0

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
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

	var rows: Array = []
	var types: Array = LevelBuilder.ENEMY_SCENES.keys()
	types.sort()
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("types="):
			types = Array(String(a).trim_prefix("types=").split(",", false))
	for t in types:
		var scene: PackedScene = LevelBuilder.ENEMY_SCENES[t]
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
		var alive := 0
		for e in spawned:
			if is_instance_valid(e):
				alive += 1
		var per_us := (ms - baseline) * 1000.0 / maxf(alive, 1)
		rows.append({"type": t, "n": alive, "ms": ms, "per_us": per_us})
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
	print("ENEMY_COST  chassis        n   phys ms   us/robot/frame")
	for r in rows:
		print("ENEMY_COST  %-12s %3d   %6.2f   %8.0f" % [r["type"], r["n"], r["ms"], r["per_us"]])
	print("ENEMY_COST_DONE")
	print("RESULT PASS")
	get_tree().quit()
