# Level System

Levels in **ai-uprising-game** are defined as structured data dictionaries rather than traditional hand-built scenes.

## Procedural Generation

All level geometry, lighting, navigations, hazards, and enemy spawns are generated procedurally at runtime using configuration profiles.

### Level Definitions
<!-- lat: { "require-code-mention": true } -->
Level profiles are stored in `scripts/levels/level_defs.gd` as dictionaries.
* Profiles define boundaries, lighting styles, obstacle layouts, and wave schedules.
* Documentation of dictionary keys can be found in [docs/LEVEL_DEF_KEYS.md](file:///C:/dev/private/ai-uprising-game/docs/LEVEL_DEF_KEYS.md).

### Level Builder
<!-- lat: { "require-code-mention": true } -->
The `level_builder.gd` script consumes level definition dictionaries and generates the 3D level layout, navigation meshes, lights, and enemy spawn locations at load time.

### Coordinate Scaling
<!-- lat: { "require-code-mention": true } -->
To maintain size consistency:
* All authored level coordinates in definitions are scaled by a multiplier: `WORLD_SCALE = 1.4`.
* Any manual positioning logic must check if the coordinate was already scaled to avoid mixed-coordinate scaling bugs.

### Exceptions
Specifies non-procedural levels and user-made content exceptions.

* **Level 1 (`level_01.tscn`):** The only hand-authored `.tscn` level file in the repository.
* **Custom Editor Levels (`level_custom.tscn`):** Loads user-made custom level layouts saved in `.lvl` formats.

## Level Editor
<!-- lat: { "require-code-mention": true } -->
The built-in level editor (`scripts/editor/level_editor.gd`, launched via `--editor`) enables rapid in-engine authoring:
* **Data Format:** Reads and writes plain data `.lvl` files and procedural dictionary profiles.
* **3D Viewport & Gizmos:** Full interactive 3D translation/rotation gizmos for placing obstacles, lights, jump pads, and spawners.
* **One-Click Playtest:** Instant in-editor simulation testing with live player spawn and telemetry verification.

## Breakable Cover
<!-- lat: { "require-code-mention": true } -->
Compact cover blocks from the `walls` def key can be shot apart, so a firefight changes the room it is fought in.

* `BreakableCover.qualifies` picks blocks 0.8-4.3 m tall, at most 6 m long, standing on the floor, with no authored point on them and no ramp or platform leaning on them; `why_not` names the reason for the rest. 35 blocks on 13 campaign levels qualify (2026-10-08 census in `tests/breakable_cover_probe`).
* HP is 60 per cubic metre (220-1400). Explosions deal x1.6, boss-weight chassis x2, ordinary enemy rounds x0.3; `EnemyBase.spawn_shockwave_ring` hits every block inside the ring, so slams wreck the arena.
* Two crack stages (66%, 33%), then a shatter: shrapnel (45 at the face, credited to whoever broke it), rubble with no collider, and `LevelBuilder.request_nav_rebake`, a debounced threaded rebake (about 1.3 ms on the main thread) so robots path through the gap.
* Chipping cover never reports a player hit, so accuracy and the AI Director's read stay clean.

## Security Firewalls
<!-- lat: { "require-code-mention": true } -->
The `firewalls` def key places energy sheets across a route that stop the player and nothing else.

* Collision layer 8 (value 128), masked only by the player body in `player.tscn` (mask 129). Layer value 16 is enemy projectiles, so it is the wrong pick.
* Robots, rounds and grenades pass, and the navmesh never sees the sheet, so enemy pathing is unchanged.
* A sheet drops when its relay node (`node`) is shot, or when every task in `opens_on` completes.
* Collision stands 1.5 m above `height`: keep firewalls out of gaps a sky-bridge threads at sheet height.
* `tests/firewall_probe` proves every relay, objective and the exit is reachable without crossing a sheet that cannot be open yet.

## Vision Scanners
<!-- lat: { "require-code-mention": true } -->
The `scanners` def key mounts sweeping surveillance heads that call reinforcements when they see the player.

* Detection needs the player's chest inside the cone, within `reach`, with a clear world-layer ray, held for `detect_time` (0.7 s).
* An alarm hands the authored `alarm` squad to the task reinforcement spawner, then the head tracks the player and cools down. `alarms` caps how often it can fire.
* The head carries a Damageable (80 HP) on the world layer: shooting it out blinds the scanner for good. Robots are never detected.
* `tests/scanner_probe` covers detection, wall occlusion and the alarm cap, and checks that every authored alarm squad lands on walkable ground with a route to the spawn.

## Escape Countdown
<!-- lat: { "require-code-mention": true } -->
An `escape` task turns a level's last stage into a timed run: the purge clock starts when the stage goes live.

* Stepping into the extraction ring (an `EscapeZone`, a `HoldZone` subclass) completes the task, which unlocks the exit portal.
* After the clock runs out, a player outside the ring takes `purge_dps` per second, so a late run still lands if there is health to spend.
* The remaining seconds live in the task label (`GameState.relabel_task`): a progress meter would read as counting up.
* Death restarts the clock in full: checkpoint respawn is in place (no reload) back at the last objective, so an expired clock would be a death loop.
* Never pair it with `kill_all`: an unwoken trigger-gated enemy would keep the exit sealed while the purge burns.
* `tests/escape_probe` checks the clock, the purge and extraction, and that every authored route runs inside 60% of its clock at sprint speed.

## Hazard Surges
<!-- lat: { "require-code-mention": true } -->
A survive wave's `flood` raises hazard beds mid-hold, so the hold changes the ground under the player instead of only adding enemies (`FloodSurge`).

* Each bed uses the def's `lava` spec (`pos`, `size`, `dmg`, `water`, `color`); `pos.y` is the height the fluid rises to, so a bed can drown decks as well as floor.
* A warning comes first: pulsing sheets mark the footprint at flood height for `warn` seconds (default 3) with a HUD alert (`warn_title`, `warn_text`). Then each bed rises 0.6 m into place over `rise` seconds as a real `LavaHazard` with no shoreline plane (`shore = false`).
* Completing the hold drains the beds (they stop burning at once, then sink and free), so the walk to the exit and the completion checkpoint are dry. `drain_title`/`drain_text` announce it.
* Death clears the beds at once and re-runs the warning when play resumes: checkpoint respawn is in place and may be on the flooded ground.
* Vulcan Forge (lava_world) floods its two ground cross-lanes and the fight moves onto the catwalks; Tidecore Basin (water_world) raises the tide over the whole low tier and the reactor cap is the last dry deck.
* `tests/flood_surge_probe` covers the warning, the rise, a dry deck over a burning floor, the death reset and the drain, then every authored flood (scaling, timing, no overlapping beds, a dry exit and decks) and the built levels.

## Haul Payload
<!-- lat: { "require-code-mention": true } -->
A `haul` task is a heavy core that has to be carried, on foot, from `pos` into an uplink ring at `to`.

* Walking into the core shoulders it and sets `GameState.carrying`. `player.gd` reads that one flag: a heavy walk (`CARRY_SPEED_MULT` x walk), sprint ignored, no dash, no grapple.
* `drop_damage` worth of hits (default 30) knocks the core 2.5 m behind the player, onto whatever floor is below. Dying drops it where the player fell.
* The HUD waypoint follows the job: the core while it is on the ground, the uplink ring while it is carried.
* `GameState.reset_tasks` clears the flag, so a level change never leaves the player slowed.
* `tests/haul_probe` checks the carry rules on the real player against an uncarried control, the drop and re-pickup, the death drop and delivery.

## Objective Placement

The builder rescues an objective or weapon pickup authored inside solid geometry by moving it to the nearest clear spot near the navmesh, and logs `Task position ... buried in geometry`.

* The test ignores the task object's own bodies (an `ObjectiveCore` is a world-layer StaticBody), and a hold or escape zone counts as clear while any point on the ring at half its radius is clear.
* Every outdoor light builds a solid mast from the floor to the lamp, so a light authored over an objective buries it. A god-ray over a target opts out with `"mast": false`.
* `tests/task_reach_probe` builds every campaign level and fails if any objective or weapon pickup moved, so the log line only ever fires for a real authoring mistake.

## Hazards and Objectives
Defines environmental challenges and mission completion criteria across generated maps.

* **Interactive Hazards:** Acid hazard pools, explosive volatile drums, moving defense laser barriers, and Tesla shock coils.
* **Mission Objectives:** Extermination waves, defense node holdouts, power core sabotage, and extraction beacon activations.
