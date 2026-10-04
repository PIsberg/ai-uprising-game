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
* Never pair it with `kill_all`: an unwoken trigger-gated enemy would keep the exit sealed while the purge burns.
* `tests/escape_probe` checks the clock, the purge and extraction, and that every authored route runs inside 60% of its clock at sprint speed.

## Hazards and Objectives
Defines environmental challenges and mission completion criteria across generated maps.

* **Interactive Hazards:** Acid hazard pools, explosive volatile drums, moving defense laser barriers, and Tesla shock coils.
* **Mission Objectives:** Extermination waves, defense node holdouts, power core sabotage, and extraction beacon activations.
