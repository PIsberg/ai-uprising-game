extends Node
## Per-physics-tick CPU time, for the headless cost instruments
## (tests/enemy_cost_probe, tests/cpu_cost_sweep).
## Usage: var clock = preload("res://tests/tick_clock.gd").attach(parent)
##        clock.reset(); ...run...; clock.percentile(0.5)

var _samples: Array[float] = []

static func attach(parent: Node) -> Node:
	var c: Node = load("res://tests/tick_clock.gd").new()
	c.name = "TickClock"
	parent.add_child(c)
	return c

func reset() -> void:
	_samples.clear()

func count() -> int:
	return _samples.size()

## p in [0, 1]; 1.0 is the maximum. Milliseconds.
func percentile(p: float) -> float:
	if _samples.is_empty():
		return 0.0
	var s := _samples.duplicate()
	s.sort()
	return s[clampi(int(round(p * (s.size() - 1))), 0, s.size() - 1)]

func _process(_d: float) -> void:
	_samples.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
