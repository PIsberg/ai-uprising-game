# Performance notes (CPU, headless)

Headless runs have no GPU, so `tests/cpu_cost_sweep` and `tests/enemy_cost_probe`
measure the pure main-thread script + physics cost. That is the number that
decides whether a busy fight stutters on a low-end CPU; render cost is measured
separately with `tools/perf_measure.tscn` (windowed).

## How to read the numbers

`Performance.TIME_PHYSICS_PROCESS` reports the cost of the **last physics tick**,
not a per-frame average (calibrated 2026-09-12: a node busy-waiting 2000 us in
`_physics_process` reads a median of 2.07 ms). Both instruments therefore report
the **median** over a window; the mean is dragged around by rare spikes. Runs on
the primary dev machine vary by up to 2x for the same configuration, so compare
ratios between variants measured in the same session, not absolute values across
sessions.

## Findings 2026-09-12 (dev machine, Godot 4.7.2, headless)

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

## Follow-up 2026-10-04 (#89)

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

**Open:** attribute the ~1 ms per active robot with the editor profiler on a
windowed run (the script profiler shows engine-side time per callback), then
decide between fewer per-tick transform writes, a cheaper child-node layout,
or a lower AI tick rate for distant robots. Tracked in the issue linked from the
PR that added these notes.
