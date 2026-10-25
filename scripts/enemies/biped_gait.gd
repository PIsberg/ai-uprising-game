class_name BipedGait
extends RefCounted
## A rigid-leg walk for static (unrigged) bipeds whose legs are their own
## parts (PartRig entries, one list per side): each leg swings about its hip
## on the body's X axis, the two in opposition, at a cadence that follows
## ground speed, and comes back under the body when it stands. A deadband
## under the creep a nav agent or a shove leaves on a standing unit (about
## 0.05 m/s) keeps the legs from twitching while it holds its ground.
## Used by the ENFORCER (trouser legs + boots) and the GUNSLINGER (legs cut
## offline); tests/biped_gait_probe.

var stride: float   ## m of ground per gait cycle
var swing: float    ## rad each leg swings either side at full speed
var deadband := 0.25 ## m/s under which the legs hang still
var _legs: Array = [] ## {entries: Array of PartRig entries, pivot: Vector3, offset: float}
var _phase := 0.0
var _amp := 0.0

func _init(stride_m: float, swing_rad: float) -> void:
	stride = stride_m
	swing = swing_rad

## `side` 0 = left (swings with phase), 1 = right (in opposition). `rest` is
## a constant turn (rad, about the hip, positive swings the foot forward)
## the leg always carries: a model shipped posed mid-stride is straightened
## by the angle its foot hangs behind its hip (the REAPER).
func add_leg(entries: Array, hip: Vector3, side: int, rest: float = 0.0) -> void:
	_legs.append({"entries": entries, "pivot": hip, "offset": 0.0 if side == 0 else PI, "rest": rest})

func is_empty() -> bool:
	return _legs.is_empty()

## Advance the stride by `speed` (ground speed, m/s) and pose every leg.
## `full_speed` is the unit's move_speed: the swing reaches `swing` there.
func tick(delta: float, speed: float, full_speed: float) -> void:
	if _legs.is_empty():
		return
	_phase = fposmod(_phase + delta * speed / stride * TAU, TAU)
	var want := swing * clampf((speed - deadband) / maxf(full_speed - deadband, 0.1), 0.0, 1.0)
	_amp = move_toward(_amp, want, delta * 3.0)
	for leg in _legs:
		var lay := PartRig.turn(leg["pivot"], Vector3.RIGHT, float(leg["rest"]) + sin(_phase + float(leg["offset"])) * _amp)
		for e in leg["entries"]:
			PartRig.pose(e, lay)

## Freeze the stride at a point of the cycle (shots): `amp` 0..1 of `swing`.
func pose_at(phase: float, amp: float) -> void:
	_phase = phase
	_amp = swing * amp
	tick(0.0, 0.0, 1.0)
