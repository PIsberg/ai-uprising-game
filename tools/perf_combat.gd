extends Node
## Headless CPU profile under combat load: no GPU, so TIME_PROCESS/PHYSICS are
## pure script. Loads a level, spawns the player + N enemies in a live fight,
## samples the CPU breakdown. This is the cost that actually stutters real play.
## Typical process/physics times come from tests/tick_clock.gd; the Performance
## TIME_* monitors hold the worst frame of the last second, so they appear here
## only as *_max1s (#89).
const LEVEL_ID := "gpt"
const TickClock := preload("res://tests/tick_clock.gd")
const N := 24
func _ready(): _go.call_deferred()
func _go():
	var lvl = load("res://scenes/levels/level_%s.tscn" % LEVEL_ID).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.0).timeout
	GameState.set_state(GameState.State.PLAYING)
	var pl = get_tree().get_first_node_in_group("player") as Node3D
	if pl == null: print("NO PLAYER"); get_tree().quit(); return
	var kinds = ["gunner","android","spider","seeker","drone","skitter","raptor","brute"]
	var here = pl.global_position
	var spawned := 0
	for i in N:
		var k = kinds[i % kinds.size()]
		var ps = load("res://scenes/enemies/%s.tscn" % k)
		if ps == null: continue
		var e = ps.instantiate()
		lvl.add_child(e)
		e.global_position = here + Vector3(cos(i)*10.0, 0.5, sin(i)*10.0)
		if "target" in e: e.set("target", pl)
		spawned += 1
	await get_tree().create_timer(1.5).timeout
	print("spawned=%d, live=%d" % [spawned, get_tree().get_nodes_in_group("enemy").size()])
	var samples := []
	var clock = TickClock.attach(self)
	for s in 24:
		clock.reset()
		for f in 5: await get_tree().process_frame
		var proc = clock.process_percentile(0.5)
		var phys = clock.percentile(0.5)
		var nav = Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS)*1000.0
		var live = get_tree().get_nodes_in_group("enemy").size()
		samples.append([proc, phys, nav, live])
		print("s=%2d live=%2d process_ms=%6.2f physics_ms=%6.2f nav_max1s=%6.2f" % [s, live, proc, phys, nav])
	print("PERF_COMBAT_DONE"); get_tree().quit()
