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

## Landmarks
<!-- lat: { "require-code-mention": true } -->
Every open-sky level gets one colossal AI megastructure past its skyline, on the spawn-to-exit heading.

* `Landmark.build_for` (from `LevelBuilder._build_landmark`) reads the `landmark` def key: `kind` (`spire`, `twin`, `dish`, `stacks`, `monolith`), `sign` (a holographic proper name; not `label`, which check_strings_csv treats as translated HUD text), `color`, `bearing`. Without the key an open-sky level gets a plain spire; interiors get none.
* Open-sky landmarks also carry `FLOCKS` (3) murmurations of lit drones (24/30/36, one MultiMesh each) whose centres orbit the structure 105-185 m up while the drones swirl around them (`_tick_flocks`; positions from `flock_point`, which the probe reads because headless runs keep no MultiMesh buffers). LOW skips them.
* Scenery only: no collision, every piece shadowless. Bodies take the fog, light bands set `disable_fog`. Built at 1x and scaled `SCALE` (1.5) whole. LOW skips steam, searchlights and halo spin.
* Interiors get `_build_core`: a lattice sphere, two rings and an eye that turns to the camera, hung under the ceiling at the candidate spot near the centre with the most clear air (`_core_spot`), `CORE_HEADROOM` over the highest walkable top within `CORE_REACH`, never near a route gate. It carries its own accent light outside the `level_light` group, so blackouts leave it burning. `ROOM_BASE_H` / `ROOM_CLEARANCE_M` mirror LevelBuilder's (the probe checks).
* An interior with no room for the core (claude: gates over the centre; guardrails and range: 6 m ceilings) gets `_build_screen` instead: a wall-sized panel on the perimeter wall the spawn faces (`screen_spot`), `SCREEN_OFF` off its face and above `SCREEN_BOTTOM`, sliding along the wall to the widest stretch clear of route gates, authored walls/platforms/towers, and, within 8 m, the hanging lamps and the exit (`_wall_blockers`). `shaders/ai_eye_screen.gdshader` draws the AI's eye; `look` shifts the pupil toward the camera, the lids blink, a Label3D types `<think>` lines under it. `LevelBuilder._build_signage` moves the facility billboard to the front wall when the screen takes the back wall (`Landmark.screen_wall`).
* Both interior AIs are fed by up to `CABLES_MAX` (8) data conduits (`_build_cables`, one MultiMesh, `shaders/data_conduit.gdshader` with each cable's length in `INSTANCE_CUSTOM.x`): strung from the perimeter walls `CABLE_DROP` under the ceiling to the core's lattice or along the screen's top bar, never below `CABLE_FLOOR` (4 m) and never through an authored wall, platform or tower (`_clear_run`). Endpoints come from `cable_ends()` for the probe.
* `tests/landmark_probe`; `tests/landmark_shot` frames each one (interiors from 14 m off the core or the screen).

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

## Prompt Injection Terminals
<!-- lat: { "require-code-mention": true } -->
The `injectors` def key places one-use consoles that jailbreak the robots around them.

* Standing in its zone types `PROMPT` over `USE_TIME` (1.5 s); stepping off backspaces it at 0.8x. Complete, it calls `EnemyBase.jailbreak(JAILBREAK_TIME)` on every robot within `RADIUS` (26 m), then reads PATCHED for good.
* `jailbreak` rides the EMP path (`_emp_t`: no perception, AI or attacks) plus `_jailbreak_t`, which spins the body and floats a `jailbreak` reasoning trace. Chassis that resist a hijack (`HIJACK_BOSS_HP`) only take `BOSS_STUN`.
* `pos` scales with the arena. `tests/injector_probe` builds each authored level and checks the terminal stands on clear floor.

## Escape Countdown
<!-- lat: { "require-code-mention": true } -->
An `escape` task turns a level's last stage into a timed run: the purge clock starts when the stage goes live.

* Stepping into the extraction ring (an `EscapeZone`, a `HoldZone` subclass) completes the task, which unlocks the exit portal.
* After the clock runs out, a player outside the ring takes `purge_dps` per second, so a late run still lands if there is health to spend.
* The remaining seconds live in the task label (`GameState.relabel_task`): a progress meter would read as counting up.
* Death restarts the clock in full: checkpoint respawn is in place (no reload) back at the last objective, so an expired clock would be a death loop.
* Never pair it with `kill_all`: an unwoken trigger-gated enemy would keep the exit sealed while the purge burns.
* `tests/escape_probe` checks the clock, the purge and extraction, and that every authored route runs inside 60% of its clock at sprint speed.

## Bonus Objectives
<!-- lat: { "require-code-mention": true } -->
A level's `bonus` is an optional challenge that pays extra score (`BonusObjective`). It never touches the exit lock.

* It lives in `GameState.level_bonus`, not `level_tasks`, so a lost bonus cannot seal a level and the mission-arc and task probes never see it.
* It stays live until the level's tasks are all done (won, `score` paid once) or the player breaks its rule (lost for the rest of the level; a death does not give it back).
* Kinds: `ghost` (trip no vision-scanner alarm, on the five scanner levels), `dry` (take no damage from a hazard bed, floods included, on the six levels where hazards are central) and `deathless` (finish without dying, +750, on the three boss levels).
* The HUD appends it to the checklist: ★ live, ✔ won, ✖ lost. Winning or losing it toasts, and the level-complete debrief lists the result on its HIGHLIGHTS line.
* `tests/bonus_objective_probe` covers winning, paying once, losing for good, the exit staying open, a non-hazard hit as the control for `dry`, the authoring rules (ghost needs scanners, dry needs beds) and the hooks on built levels.

## Jam-Shielded Relays
<!-- lat: { "require-code-mention": true } -->
A `destroy_core` task with `jam_shielded` is immune until one of the player's jam zones covers it, the same rule as a hive unit's shield (`ObjectiveCore.jam_shielded`).

* A JamZone only detects the enemy layer and a core sits on the world layer, so the core measures its own distance to live `jam_zone` nodes each frame and toggles `Damageable.invulnerable`.
* A hit on the closed shield flares the bubble and teaches the move once ("plant a jam beacon on it").
* Only author it on a level with a `jammer` def, or the core can never die. Relay Node 9 (hivemind) stages the HIVE PRIME behind two of them.
* `tests/jam_relay_probe` covers the shield rules against an unshielded control, the jammer invariant, and the staged PRIME on the built level.

## Weather Shifts
<!-- lat: { "require-code-mention": true } -->
A survive wave's `weather` turns the level's own Environment against the player for the rest of the hold (`WeatherShift`).

* The distance fog thickens by `fog_mult` and can shift to `fog_color` over `fade` seconds; `gust` speeds up the level's weather particles (the builder names the snow emitter "Weather").
* Robots do not lose sight in fog, so keep the multiplier where near cover still reads: frostbreak's whiteout is x2.5 (x4.5 hid the yard inside 20 m).
* Completing the hold eases every value back to what it was captured at, then the node frees itself. Death does not reset it: fog cannot kill a respawned player.
* A blackout (`blackout`) cuts the level's lights, their lit fixture panels, the ULTRA VoxelGI and the god-ray shafts (group `level_light`), with `ambient_mult` and `exposure_mult` dimming the rest. The cut lights alone darkened sublevel by 7%, because emissives carry its frame; with `exposure_mult` 0.55 it is 24%. Alarm beacons and pickup glows stay lit.
* A task can carry the same `weather` spec as a wave: it starts when that stage goes live and clears when it completes. Sublevel's night-shift quota is fought in a blackout.
* A level with no weather of its own can raise some for the storm (`particles`: dust, snow or rain). The shift owns those particles, then stops and frees them when the hold is won.
* Frostbreak's thaw hack now breaks its blizzard into a 30 s whiteout hold, and desert's counterstrike hold is a sandstorm with raised dust.
* `tests/weather_shift_probe` covers the shift and the restore, that every authored shift thickens the fog inside its hold, that a `gust` only appears where there are weather particles (the level's own or raised), the built level's real Environment, and that raised particles are freed after the storm.

## Hazard Surges
<!-- lat: { "require-code-mention": true } -->
A survive wave's `flood` raises hazard beds mid-hold, so the hold changes the ground under the player instead of only adding enemies (`FloodSurge`).

* Each bed uses the def's `lava` spec (`pos`, `size`, `dmg`, `water`, `color`); `pos.y` is the height the fluid rises to, so a bed can drown decks as well as floor.
* A warning comes first: pulsing sheets mark the footprint at flood height for `warn` seconds (default 3) with a HUD alert (`warn_title`, `warn_text`). Then each bed rises 0.6 m into place over `rise` seconds as a real `LavaHazard` with no shoreline plane (`shore = false`).
* Completing the hold drains the beds (they stop burning at once, then sink and free), so the walk to the exit and the completion checkpoint are dry. `drain_title`/`drain_text` announce it.
* Death clears the beds at once and re-runs the warning when play resumes: checkpoint respawn is in place and may be on the flooded ground.
* A task can carry the same `flood` spec: it rises when that stage goes live and drains when it completes. Mistral's coolant channels overflow for as long as the cryo-core stands.
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
