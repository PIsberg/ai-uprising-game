extends Node
## The per-tick CPU instrument reads a known tick cost correctly (#89).
## A rig node busy-waits BUSY_MS in every physics tick and SPIKE_MS in one tick
## per second, the shape of a real fight: a steady per-tick cost plus rare
## hitches (SoundSynth building a stream, a scene instantiating). A typical tick
## must read about BUSY_MS, never the spike.
##
## Performance.TIME_PHYSICS_PROCESS cannot do this: main.cpp sets it once a
## second to the WORST tick of that second (physics_process_max), so the median
## of per-frame reads is the spike. tests/enemy_cost_probe and
## tests/cpu_cost_sweep read it that way and reported ~1 ms per robot per tick;
## the editor-profiler data (tools/remote_profile.gd) says ~0.08 ms.
##   godot --headless --path . --audio-driver Dummy res://tests/tick_clock_probe.tscn

const BUSY_MS := 2.0
const SPIKE_MS := 50.0
const SAMPLE_SEC := 3.0
const TickClock := preload("res://tests/tick_clock.gd")

var _ok := true
var _ticks := 0

class Rig extends Node:
	var busy_ms := 0.0
	var spike_ms := 0.0
	var _n := 0
	func _physics_process(_d: float) -> void:
		_n += 1
		var ms := spike_ms if _n % Engine.physics_ticks_per_second == 0 else busy_ms
		var until := Time.get_ticks_usec() + int(ms * 1000.0)
		while Time.get_ticks_usec() < until:
			pass

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var rig := Rig.new()
	rig.busy_ms = BUSY_MS
	rig.spike_ms = SPIKE_MS
	add_child(rig)
	var clock = TickClock.attach(self)
	for i in 30:
		await get_tree().physics_frame
	clock.reset()
	var t := 0.0
	while t < SAMPLE_SEC:
		await get_tree().process_frame
		t += get_process_delta_time()
	var p50: float = clock.percentile(0.5)
	var p99: float = clock.percentile(0.99)
	print("tick clock: %d ticks, p50 %.2f ms, p99 %.2f ms, max %.2f ms (rig: %.1f ms per tick, %.0f ms once a second)"
		% [clock.count(), p50, p99, clock.percentile(1.0), BUSY_MS, SPIKE_MS])
	if clock.count() < int(SAMPLE_SEC * Engine.physics_ticks_per_second * 0.5):
		_bad("only %d ticks sampled in %.0f s" % [clock.count(), SAMPLE_SEC])
	if p50 < BUSY_MS * 0.9 or p50 > BUSY_MS * 1.6:
		_bad("typical tick read %.2f ms, the rig spends %.1f ms" % [p50, BUSY_MS])
	if clock.percentile(1.0) < SPIKE_MS * 0.9:
		_bad("the %.0f ms spike was not seen (max %.2f ms)" % [SPIKE_MS, clock.percentile(1.0)])
	print("RESULT %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

func _bad(msg: String) -> void:
	_ok = false
	print("BAD  " + msg)
