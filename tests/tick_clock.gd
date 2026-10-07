extends Node
## Per-physics-tick CPU time, for the headless cost instruments
## (tests/enemy_cost_probe, tests/cpu_cost_sweep). tests/tick_clock_probe
## calibrates it against a known busy-wait.
##
## Do not use Performance.TIME_PHYSICS_PROCESS for this: main.cpp sets it once a
## second to the WORST physics tick of that second, so medians of it measure the
## spikes, not the typical tick (#89: it put ~1 ms per robot on a ~0.08 ms cost).
##
## How: this node runs the first physics callback of each tick
## (process_physics_priority at the minimum) and the first process callback of
## the frame (process_priority at the minimum). The time between the two is one
## physics step as the main loop runs it: every node's physics callback, the
## navigation server, the physics server step, deferred calls and the end of
## the iteration. It leaves out the physics server sync and query flush that run
## before the first callback (Area3D signals). When a frame runs several steps,
## the last one is sampled.
##
## Process (idle) time per frame is bracketed the same way, from this node's
## process callback to a child's that runs last (process_priority at the
## maximum): every node's _process, without the deferred-call flush after it.
## Performance.TIME_PROCESS has the same once-a-second-maximum problem.
## Usage: var clock = preload("res://tests/tick_clock.gd").attach(parent)
##        clock.reset(); ...run...; clock.percentile(0.5)

const FIRST := -2147483647
const LAST := 2147483647

class Tail extends Node:
	var clock: Node
	func _process(_d: float) -> void:
		clock._process_end()

var _samples: Array[float] = []
var _tick_start := 0
var _pending := false
var _proc: Array[float] = []
var _proc_start := 0

static func attach(parent: Node) -> Node:
	var c: Node = load("res://tests/tick_clock.gd").new()
	c.name = "TickClock"
	parent.add_child(c)
	return c

func _ready() -> void:
	process_physics_priority = FIRST
	process_priority = FIRST
	var tail := Tail.new()
	tail.clock = self
	tail.process_priority = LAST
	add_child(tail)

func reset() -> void:
	_samples.clear()
	_proc.clear()
	_pending = false

func count() -> int:
	return _samples.size()

## Physics tick time; p in [0, 1], 1.0 is the maximum. Milliseconds.
func percentile(p: float) -> float:
	return _pct(_samples, p)

## Process (idle) time per frame; same convention.
func process_percentile(p: float) -> float:
	return _pct(_proc, p)

static func _pct(values: Array[float], p: float) -> float:
	if values.is_empty():
		return 0.0
	var s := values.duplicate()
	s.sort()
	return s[clampi(int(round(p * (s.size() - 1))), 0, s.size() - 1)]

func _physics_process(_d: float) -> void:
	_tick_start = Time.get_ticks_usec()
	_pending = true

func _process(_d: float) -> void:
	_proc_start = Time.get_ticks_usec()
	if _pending:
		_samples.append((_proc_start - _tick_start) / 1000.0)
		_pending = false

func _process_end() -> void:
	_proc.append((Time.get_ticks_usec() - _proc_start) / 1000.0)
