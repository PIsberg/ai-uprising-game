extends Node
## Report-only CPU instrument for Last Stand (horde mode), the backlog's stress
## case: starts waves 8, 11, ... 23 back to back against an invulnerable player
## so the crowd grows to ~60, and after each prints the enemy count with the
## physics tick and process frame (tests/tick_clock.gd) p50/p90/max. Findings in
## docs/PERF_NOTES.md. Headless = CPU only; GPU cost needs a windowed run.
##   godot --headless --path . --audio-driver Dummy res://tests/horde_cost_probe.tscn
const TickClock := preload("res://tests/tick_clock.gd")
func _ready() -> void:
	_run.call_deferred()
func _find_director(n: Node) -> Node:
	if n.get_script() and String(n.get_script().resource_path).ends_with("horde_director.gd"):
		return n
	for c in n.get_children():
		var d := _find_director(c)
		if d: return d
	return null
func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	var lvl: Node = load("res://scenes/levels/level_horde.tscn").instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.5).timeout
	var pl := get_tree().get_first_node_in_group("player")
	pl.get_node("Damageable").invulnerable = true
	var dir := _find_director(lvl)
	dir.set("_lull", 9999.0)
	# _start_wave saves a new best wave to user://records.cfg; a probe must never
	# overwrite the player's record (an earlier version of this run set it to 24).
	dir.set("best", 1 << 30)
	var clock = TickClock.attach(self)
	for step in 6:
		dir.set("wave", 8 + step * 3)
		dir.call("_start_wave")
		await get_tree().create_timer(8.0).timeout
		clock.reset()
		var t := 0.0
		while t < 3.0:
			await get_tree().process_frame
			t += get_process_delta_time()
		var n := get_tree().get_nodes_in_group("enemy").size()
		print("HORDE enemies=%3d  phys p50 %5.2f p90 %5.2f max %6.2f ms   proc p50 %5.2f p90 %5.2f ms   ticks=%d" % [n,
			clock.percentile(0.5), clock.percentile(0.9), clock.percentile(1.0),
			clock.process_percentile(0.5), clock.process_percentile(0.9), clock.count()])
	print("RESULT PASS")
	get_tree().quit()
