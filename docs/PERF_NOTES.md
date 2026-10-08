# Performance notes (CPU, headless)

Headless runs have no GPU, so `tests/cpu_cost_sweep` and `tests/enemy_cost_probe`
measure the pure main-thread script + physics cost. That is the number that
decides whether a busy fight stutters on a low-end CPU; render cost is measured
separately with `tools/perf_measure.tscn` (windowed).

## How to read the numbers

Both instruments time each physics tick with `tests/tick_clock.gd`: a node that
runs the first physics callback of the tick and the first process callback of
the frame, so the gap is one step as the main loop runs it (every node's physics
callback, the navigation server, the physics step, deferred calls). It leaves
out the physics server's sync and query flush before the first callback.
`tests/tick_clock_probe` (suite) calibrates it: a rig spending 2 ms per tick plus
50 ms once a second reads a median of 2.03 ms. They report the **median** tick;
the mean is dragged around by rare spikes. Repeat runs agree to within ~10%.

**Do not use `Performance.TIME_PHYSICS_PROCESS`, `TIME_PROCESS` or
`TIME_NAVIGATION_PROCESS` for this.** `main.cpp` (4.7.2, lines 5121-5141) sets
them once a second to the **worst** tick or frame of that second. A median of
per-frame reads is the spike: the same rig reads 50.04 ms. Every number in the
two sections below dated 2026-09-12 and 2026-10-04 was read that way and is
wrong; they are kept only for the record of what was tried. The 2026-09-12
"calibration" (a constant 2 ms busy-wait read 2.07 ms) could not catch this,
because for a constant cost the worst tick is the typical tick.

For attribution (which function, which physics stage), `tools/remote_profile.gd`
is the headless stand-in for the editor's Profiler tab: it runs a scene in a
child process under `--remote-debug`, enables the engine's "servers" profiler
with native calls recorded, and prints per-tick percentiles, the physics
server's step breakdown and the top script functions by self time.

## Corrected findings 2026-10-08 (#89)

Per-chassis rig (`enemy_cost_probe`, 8 woken copies, 2 for bosses), two runs:

| chassis | us per robot per tick |
|---|---|
| colossus | 138-141 |
| drone | 73-74 |
| android | 62-67 |
| spider | 46-47 |

The old instrument had put the android at 700-1300 us and the colossus at
12-14 ms. `tools/remote_profile.gd` on 8 woken androids agrees independently:
whole-tick p50 0.62 ms, p90 1.32 ms (about 75 us per robot with the player).
`tools/perf_combat.tscn` with 28 robots fighting on gpt: 1.5-3.4 ms per tick.

Campaign sweep (`cpu_cost_sweep`, every enemy present 2.4 s after load woken
onto the player): physics median 0.36-1.02 ms per tick on all 24 levels, p90
under 1.4 ms, process median 0.24-0.42 ms per frame, no level flagged HOT. The
worst single ticks (5-7 ms on suburb_boss, convoy, assembly, sublevel,
frostbreak, water_world, neon, lava_world) are one-offs inside the sample window,
not a steady cost.

So an 8-robot fight costs well under 1 ms of a 16.7 ms frame on the dev CPU.
There is no per-robot physics problem to fix; #89 is closed on this evidence.

## Horde stress (Last Stand), 2026-10-08

`tests/horde_cost_probe` starts waves 8 to 23 back to back against an
invulnerable player, so the crowd only grows. Two runs:

| enemies alive | physics p50 / p90 ms | process p50 / p90 ms |
|---|---|---|
| 8 | 0.67-0.73 / 1.04-1.06 | 0.24-0.26 / 0.38-0.39 |
| 19-23 | 1.06-1.67 / 1.46-2.16 | 0.40-0.56 / 0.56-0.76 |
| 38-40 | 2.00-2.62 / 2.81-3.24 | 0.86-0.92 / 1.06-1.20 |
| 54-63 | 3.56-3.71 / 4.72-4.99 | 1.41-1.71 / 1.71-1.97 |

Linear at roughly 55 us of physics and 25 us of process per robot. Sixty robots
cost about 5.5 ms of CPU per frame, a third of the 60 fps budget, so horde mode
is not CPU-bound on the dev machine. Single ticks peak at 5-8 ms (spawn
telegraphs instantiating). The GPU side (draw calls and lights per tier with 60
robots) still needs a windowed run.

## Findings 2026-09-12 (SUPERSEDED: read from the once-a-second worst-tick monitor)

Campaign sweep (`cpu_cost_sweep`, every enemy woken onto the player):

| level | enemies | physics ms/tick, full fight | with enemy scripts frozen |
|---|---|---|---|
| gpt | 5 | 1.2 | 1.1 |
| gemini | 7 | 7.8 | 5.1 |
| suburb_boss | 5 | 6.2 | 1.3 |
| claude | 12 | 8.7 | 2.9 |
| assembly | 5 | 7.0 | 1.1 |
| water_world | 8 | 6.7 | 2.6 |
| lava_world | 9 | 5.8 | 2.6 |

Process (idle-frame) time is 1.3-3 ms everywhere. Physics time is where the
levels differ, and it collapses when the enemies' `_physics_process` is
disabled, so it is enemy per-tick work.

Per-chassis rig (`enemy_cost_probe`, 8 copies on a flat navmesh, woken):
every chassis costs roughly **0.5-1.5 ms per robot per physics tick** (android
~1.3, drone ~1.0, spider ~0.6, server ~0.3); bosses more (colossus ~12-14 ms
per copy). Eight androids alone are ~10 ms of a 16.7 ms frame.

Additive isolation (separate process per variant, 8 androids, median of 4 s):

| variant | us per copy per tick |
|---|---|
| bare CharacterBody3D + capsule | 7 |
| + NavigationAgent3D, avoidance on | 21 |
| + NavigationAgent3D, avoidance off | 8 |
| full android scene, idle | 700-1200 |
| full scene, enemy `_physics_process` disabled | 63 |
| full scene, `_run_state()` skipped | 112 |

So the cost is gated by the enemy state machine, yet wall-clock timers around
the script's own calls (`_perceive`, `_run_state`, `move_and_slide`, the
locomotion audio) sum to only ~50 us per robot-tick. The remaining ~1 ms per
robot is engine work that the state logic triggers and that runs later in the
same physics tick (transform-change propagation to the ~30 child nodes, physics
or navigation server sync, or deferred calls). Skipping the per-tick body
rotation, freeing the RobotModel, the lights, the audio players or the
particles did not move the number decisively inside the noise. Navigation
avoidance is enabled on 21 enemy scenes but nothing consumes `velocity_computed`;
it measured only ~13 us per robot, so it is not the cost.

## Follow-up 2026-10-04 (#89; SUPERSEDED, same monitor)

- `enemy_cost_probe` had hung on a script error since the lazy scene tables
  (#94) turned `ENEMY_SCENES` into paths; it now uses `LevelBuilder.enemy_scene`.
- The physics server is not the cost. With 8 woken robots of each chassis, the
  server reports 9-12 collision pairs, 8 active objects and 8-11 islands, against
  1 / 0 / 0 for the player and floor alone. Broadphase and contact work for a
  handful of pairs cannot add up to milliseconds.
- Jolt does not help measurably. Five interleaved processes each (8 androids,
  `physics/3d/physics_engine` through a temporary override.cfg): medians 1904 us
  per robot (GodotPhysics3D) and 3728 us (Jolt).
- Tick timing on the dev machine was far noisier that day than the 2x noted
  above: one config read 283 to 52827 us per robot across runs, and two chassis
  once reported the identical median, which suggests `TIME_PHYSICS_PROCESS` was
  re-read from the same tick across frames. Headless timing cannot attribute this
  further; the profiler step below is still the way.

~~Open: attribute the ~1 ms per active robot with the editor profiler.~~
Resolved 2026-10-08: there was no ~1 ms; see "Corrected findings" above.
