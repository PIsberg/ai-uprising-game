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
* Night skies (env `stars`) also get `_build_aurora`: one ribbon on an arc `AURORA_R` behind the landmark, `AURORA_FOOT` to `AURORA_CROWN` up (180-330 m in the world), drawn by `shaders/data_aurora.gdshader` (folding curtain, falling data columns, fog off). `custom_aabb` covers the shader's folds. LOW skips it.
* The overlord watches over every open-sky level that has a landmark: `OverlordHolo.build_for` (also from `_build_landmark`) hangs a wireframe face (`shaders/overlord_face.gdshader`, one quad) `BEARING_DEG` (48) round from the landmark and `DIST_PAST_FLOOR` (640 m) past the floor, `ELEVATION_DEG` (30) up, `HEIGHT` (300 m) tall (`spot_for`). It turns to the camera with a lag its pupils make up, blinks, tears like a bad signal, and mouths every HUD taunt: `hud._overlord_say` sends `GameState.overlord_spoke`, which runs its equalizer mouth for `TALK_PER_CHAR` per character. `Skyline.plan` keeps far towers out of `FACE_CLEAR` of it and near towers under `FRAME_H` within `FACE_FRAME`. Alpha-blended over a dark fill so it reads on day skies too; LOW keeps it. `tests/overlord_holo_probe`; `tests/overlord_holo_shot`.
* Scenery only: no collision, every piece shadowless. Bodies take the fog, light bands set `disable_fog`. Built at 1x and scaled `SCALE` (1.5) whole. LOW skips steam, searchlights and halo spin.
* Interiors get `_build_core`: a lattice sphere, two rings and an eye that turns to the camera, hung under the ceiling at the candidate spot near the centre with the most clear air (`_core_spot`), `CORE_HEADROOM` over the highest walkable top within `CORE_REACH`, never near a route gate. It carries its own accent light outside the `level_light` group, so blackouts leave it burning. `ROOM_BASE_H` / `ROOM_CLEARANCE_M` mirror LevelBuilder's (the probe checks).
* An interior with no room for the core (claude: gates over the centre; guardrails and range: 6 m ceilings) gets `_build_screen` instead: a wall-sized panel on the perimeter wall the spawn faces (`screen_spot`), `SCREEN_OFF` off its face and above `SCREEN_BOTTOM`, sliding along the wall to the widest stretch clear of route gates, authored walls/platforms/towers, and, within 8 m, the hanging lamps and the exit (`_wall_blockers`). `shaders/ai_eye_screen.gdshader` draws the AI's eye; `look` shifts the pupil toward the camera, the lids blink, a Label3D types `<think>` lines under it. `LevelBuilder._build_signage` moves the facility billboard to the front wall when the screen takes the back wall (`Landmark.screen_wall`).
* Both interior AIs are fed by up to `CABLES_MAX` (8) data conduits (`_build_cables`, one MultiMesh, `shaders/data_conduit.gdshader` with each cable's length in `INSTANCE_CUSTOM.x`): strung from the perimeter walls `CABLE_DROP` under the ceiling to the core's lattice or along the screen's top bar, never below `CABLE_FLOOR` (4 m) and never through an authored wall, platform or tower (`_clear_run`). Endpoints come from `cable_ends()` for the probe.
* `tests/landmark_probe`; `tests/landmark_shot` frames each one (interiors from 14 m off the core or the screen).

## Skyline
<!-- lat: { "require-code-mention": true } -->
Every open-sky level is ringed by the overlord's megacity, past the perimeter wall and in front of the landmark.

* `Skyline.build_for` (from `LevelBuilder._build_skyline`, which keeps the ground apron) builds `Skyline.plan(def)`: a near ring of `NEAR_COUNT` towers and a far ring of up to `FAR_COUNT`, each a base box plus 0-2 setback tiers and sometimes an antenna, with a beacon on the top box. Rings are placed by clearance from the floor rectangle (`_place`), not by radius: a shallow bearing on CONVOY's 44 x 380 m floor left 8 m of a 22 m ray gap.
* The landmark (`Landmark.heading_for`) stays framed: no far tower inside `LANDMARK_CLEAR`, near towers inside `LANDMARK_FRAME` capped at `FRAME_H` with no tiers.
* Draws: one MultiMesh for every box (`shaders/skyline_tower.gdshader`: a window grid in metres from the instance scale; `INSTANCE_CUSTOM` carries seed, lit fraction and whether the box has windows), one for the beacons (fog off, blinking together), one for the `SIGN_COUNT` sign panels, plus a Label3D per sign. Shadowless, no collision. The plan is seeded from the level name and floor, so a level always gets the same city.
* `tests/skyline_probe` checks the plan for every open-sky level and the built draws; `tests/landmark_shot` frames it.

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

## Stamping Presses
<!-- lat: { "require-code-mention": true } -->
The `presses` def key builds hydraulic stamping presses: a head that slams a striped footprint once a period and crushes whatever is under it.

* The head cocks for a telegraph (red lamps, glowing lip) before it drops; a player in the footprint at the slam takes `dmg` (45), once, and is shoved out of an open side. Robots are never hurt (traps are for the player; the zone only watches the player layer).
* Pillars stand at the ends of the footprint's long axis and, with the beam, are solid world geometry the navmesh bakes round. The head has no collision, so the footprint stays walkable and nothing wedges in it.
* `phase` (0..1 of a period) staggers a line so the slam travels down it. Pos and size scale with the world; clearance does not.
* The Assembly builds one into the east freight bulkhead's gap and a line of three across the dock lane, so the meltdown run times them.
* `tests/stamp_press_probe` covers the hit, the shove, the crush, the telegraph and the phase, and checks the bulkhead press covers the scaled gap.

## Ziplines
<!-- lat: { "require-code-mention": true } -->
The `ziplines` def key strings a two-way cable between two decks.

* A `ZipLine` stands a pylon at each end (`a`, `b`, points on the decks) with a glowing cable between their heads. Stepping into a station calls `Player.zipline_to` (the convoy's scripted ride) with an anchor 1 m over the other deck: the tether winches the player along and the ride ends on that deck. Jump lets go mid-ride. Ziplines cost no stamina.
* The far station ignores the player until they step off it, so arriving never sends them straight back. Robots do not ride.
* Both ends scale with the world on the ground plane; heights stay authored. Keep the straight line between the stations clear at chest height: the winch pulls in a line.
* TITAN runs one from the east tower roof (off the sky-bridge landing) over the boss floor to the south-west deck. ARCHON runs one from the south tower roof to the south-west deck, clear of the floor where the boss fights (a winch ride into the boss's body would wedge).
* `tests/zipline_probe` rides one both ways without bouncing back, checks robots stay put, every zipline level's ends sit on a tower roof and a deck with a clear line between, and rides each in its built level.

## Fire Vents
<!-- lat: { "require-code-mention": true } -->
The `fire_vents` def key builds floor fire vents: a round grate inside a yellow-and-black hazard ring that erupts a column of flame once a period.

* Every eruption is warned for 1.2 s (`WARN_TIME`): the grate glows from dull red to orange, flames lick up through it, an orange light swells, the ring pulses and it rumbles. The column then burns for 1.2 s (`ERUPT_TIME`).
* While it erupts, the player standing on it takes `dmg` (12) every 0.25 s. Robots are never hurt: traps are for the player. Vents are in the `hazard` group (they count against the "dry" bonus) and have no collision.
* `phase` (0..1 of a period) staggers a row so the eruption rolls across it. Pos scales with the world; `radius` (1.4) and `height` (3.2) stay authored.
* The first vent a player sees warming up, from within 7 m of its ring, teaches the rule once per run through `GameState.teach_once`.
* The Crucible floors both bulkhead gaps with a row of three, a third of a period apart, so the way in and the meltdown run out both cross a row with two vents always cold.
* LAVA WORLD puts one on each recycler walkway (two, half a period apart, on the long east one). On a walkway there is no stepping round a vent, so the player waits at the ring for its cold beat; `radius` 1.5 keeps the ring on the scaled 3.64 m walkway and leaves 0.14 m at the edge.
* `cryo: true` makes a coolant vent: the same beats and damage, but the grate frosts over blue-white and hisses, the blast is white-blue vapour, and it teaches its own line ("CRYO VENT"). MISTRAL's cryo-core puts a row of three across its east gap (radius 1.6 so the row spans the wider 8 m gap), a third of a period apart like the Crucible's.
* `tests/fire_vent_probe` checks the warning lead and look, who burns and when, the hint, the cryo look and hint, the Crucible and MISTRAL gap rows and the LAVA WORLD walkway vents.

## Pendulum Blades
<!-- lat: { "require-code-mention": true } -->
The `pendulums` def key stands a gantry across a walkway with a toothed blade swinging across the path under it.

* Two posts `width` apart (across the path, `path` "z" or "x"), a crossbeam 4 m up, an arm 3.25 m long, a 0.75 m blade swinging 70 degrees either side once every `period` (2.6 s). Through the bottom of the swing it sweeps the whole walkway at body height, so there is no lane round it: you time it.
* The gantry says when. A big sign on the crossbeam reads GO (green) when the blade will not reach the player's spot across the walkway, at standing height, for the next `LOOKAHEAD` (0.5 s), and WAIT (red) when it will; the lamps on both posts match. A striped band marks the cut on the floor. The lookahead is what makes GO safe for a player who turns up late in a window, not just at its start.
* A blade that catches the player costs `damage` (30) and throws them along the path. Robots are not hit. The first gantry a player walks up to teaches the rule once per run.
* Position and `width` scale with the world (the walkway does); pivot height and arm stay authored. No collision; in the `hazard` group.
* LAVA WORLD stands two on the long west walkway and one on the south walkway of its outer ring, their posts in the slag either side.
* `tests/pendulum_blade_probe` checks there is no safe lane, the sign, a hit and its shove, 20 careful crossings on GO without a hit (and 7 hits with the lookahead off), a careless walker getting hit, the hint and the LAVA WORLD placement.

## Shock Floors
<!-- lat: { "require-code-mention": true } -->
The `shock_floors` def key lays an electrified tile floor that arcs in a pattern.

* A grid of `cells` tiles, `cell` metres square. `pattern` "checker" splits them into the two colours of a chessboard, so every tile's four neighbours are in the other group; "rows" makes one group per row, a wave. The groups take turns: a group glows for `WARN_TIME` (0.9 s), then arcs for `ZAP_TIME` (0.7 s).
* The read is one rule: a glowing tile is about to arc, a dark tile is safe. A glowing tile has a dim pulsing fill and a border that thickens as it charges; an arcing one turns electric blue with white crackle and throws bolts up off it. Every tile's outline is lit at all times, so the floor reads before it does anything.
* Feet on an arcing tile (within 0.35 m of it) take `dmg` (12) every 0.3 s; a jump clears it. Robots are not hurt, so robots placed near a floor do not die before the player arrives. The first floor a player walks up to teaches the rule once per run.
* Position and `cell` scale with the world. No collision; in the `hazard` group.
* The Neon Arcade lays a 4 x 2 checker just inside its north gap, from the bulkhead's inner face, so coming in from the spawn you cross it. Its two x = +-7 lane strips stop short of it (34 long, not 40): a cyan strip through it read as part of it.
* `tests/shock_floor_probe` checks the turns and warning lead, the checker's dark neighbours, who is hit and when (standing, mid-jump, off the floor, robots), the hint and the Neon placement.

## Floor Saws
<!-- lat: { "require-code-mention": true } -->
The `saws` def key builds floor saws: a spinning blade that runs a slot in the floor from `a` to `b` and back, for ever.

* The lane either side of the slot (`LANE_HALF`, 0.55 m) is painted in hazard stripes, and the stripes are the danger. A blade passing a body in the lane cuts it: the player takes `dmg` (25), once per 0.7 s, and is thrown out of the lane to their side. Robots are never cut: traps are for the player.
* It is jumpable: the blade's top is 0.85 m up (`BLADE_TOP`), under a jump's 1.17 m apex. Stepping out of the stripes also clears it.
* It is always telegraphed: the blade is out of the slot and whines, the end lamp it runs toward blinks red, and a player standing in its lane gets a blip and a flash of the stripes `WARN_LEAD` (0.7 s) before it reaches them, once per approach. The first saw a player walks up to (within 6 m of the lane) teaches the rule once per run through `GameState.teach_once`.
* `speed` (4.5 m/s), `pause` (0.5 s at each end) and `phase` (0..1 of a round trip). Both ends scale with the world. No collision; in the `hazard` group.
* The Assembly guards its north entry gap with two slots, one either side of the bulkhead, running opposite ways; each blade reaches to 0.5 m of the gap's edges, too narrow to slip past.
* The suburb (Maple Grove) runs two slots across its canal bridge's deck (the low crossing), half a round trip apart; each blade cuts to within a body's radius of both deck edges, so there is no sneaking along the rail, and the tower sky-bridge stays the safe high road. A saw's `a` and `b` carry the deck's height (y is authored).
* `tests/floor_saw_probe` checks the travel, cuts and warning lead, the jump and the step-out, the shove, robots, the hint, the Assembly slots and the suburb bridge slots.

## Laser Sweeps
<!-- lat: { "require-code-mention": true } -->
The `laser_sweeps` def key builds a rotating laser fence: beams spinning round a centre at fixed heights.

* Default beams: one at 0.45 m (jump it) and one at 1.35 m (crouch or slide under it: the player stands 1.8 m, crouches 1.0 m). A beam touching the player's capsule hurts (`damage`, once per pass per beam); robots are never hit.
* Each beam shows how to beat it: under 0.9 m it is a jump beam (amber, a JUMP tag riding over it), at or over 0.9 m a duck beam (red, a DUCK tag riding under it). A beam about to reach a player inside its reach blips (high pitch for jump, low for duck) and flashes its tag `WARN_LEAD` (0.6 s) ahead, once per pass. The first fence a player walks up to (within 4 m of its reach) teaches the rule once per run through `GameState.teach_once`.
* Each beam is raycast against the world every tick and stops at the first wall, so cover still covers. `inner` starts the beams clear of what they spin round; `post: false` hides the emitter post when a core is the emitter.
* `wakes_on` / `stops_on` take task ids (listened to through `GameState.tasks_changed`). Position scales with the world; radius and heights stay authored.
* GROK's mainframe sweeps the room round it from the moment its enforcer (HVT) dies until the core is destroyed. The CLAUDE vault spins one round its decrypt zone from the keycard to the end of the decryption, so the 12 s hold is held over the beams.
* `tests/laser_sweep_probe` checks stand/crouch against the high beam, floor/jump against the low one, the colours, tags, warning lead and teach toast, a wall stopping a beam, `stops_on`, and GROK's and CLAUDE's placement.

## Laser Gates
<!-- lat: { "require-code-mention": true } -->
The `laser_gates` def key strings a laser hurdle across a gap: a knee beam (0.45 m, jump it) and a chest beam (1.35 m, duck under it) between two posts, only one live at a time.

* The beams swap every half `period` (3.2 s). The beam about to light flickers for `WARN_TIME` (0.7 s) first, so the player sees which move is coming. The live beam is drawn solid in the Laser Sweeps colours (amber to jump, red to duck) with its JUMP / DUCK tag over the middle of the gap; a flickering or dark beam never hurts.
* Touching the live beam costs `damage` (15), once per 0.5 s. Robots are never hit. The first gate a player walks up to teaches the rule once per run.
* `axis` is the world axis the beams run along; `phase` (0..1 of a period) offsets gates. Position and `width` scale with the world; heights stay authored.
* Skybridge Uplink strings one across each blast door (the z = -16 and z = 16 gaps), half a period apart, so the two doors never match.
* Gemini (campaign slot 3) strings the campaign's first one across its roofed conduit's mouth, slower than any later gate (period 4.4 s, each beam lit 2.2 s), so the JUMP / DUCK read is learned before the vault and the uplink ask for it at speed.
* `tests/laser_gate_probe` checks the alternation and flicker lead, the tags, who is hit standing, crouched and mid-jump, the hint, the Uplink placement, and that the campaign's first gate is Gemini's, its slowest, spanning the conduit's mouth.

## Jump Pads
<!-- lat: { "require-code-mention": true } -->
The `jump_pads` def key places launch pads that throw the player onto a deck.

* A `JumpPad` (an `Area3D` on the player layer) solves a ballistic arc from where the player stands to `to`, topping out 2 m above the higher end or at `max_apex`, and hands it to `Player.launch`. Robots are not launched.
* Indoors the builder caps every arc under the room's ceiling with head room (`room_h - 2.0`, the same room height `_build_geometry` uses).
* Both ends scale with the world on the ground plane; heights stay authored. Aim `to` at the deck's real surface (a tower roof is at the tower's height, not its stair top).
* NEON ARCADE has three: floor to the north balcony, floor to the west deck, and a long throw onto the tower roof. ALIEN (open sky, no cap) has two bounce pods from the crater floor onto its two tower roofs.
* `tests/jump_pad_probe` checks a pad lands on its deck, a capped arc stays under its cap, robots stay down, every pad level's pads aim at decks (and clear the ceiling indoors), and a ride from each pad in each built level lands on target.

## Ladle Cranes
<!-- lat: { "require-code-mention": true } -->
The `ladle_crane` def key builds an overhead bridge crane that hunts the player with a ladle of molten metal.

* It rides two runway rails under the roof across its coverage (`span_x` by `span_z`, scaled with the world; rail `height` authored). A player inside the coverage (or within 3 m of it) is followed; outside it the crane waits.
* Each pour is telegraphed: the ladle stops over the player, a red ring pulses on the floor and the ladle tilts for 1.4 s. Then a molten pool (a recoloured `LavaHazard` with the amber hazard border, burns the player only) lies there for 6 s. One pour every `period` s.
* Keep the coverage clear of towers, sky-bridges and tall hero pieces: the ladle hangs 4.2 m under the rails.
* The Crucible's crane covers the east half of the foundry floor, from the second forge ring to the pour-gate.
* `tests/ladle_crane_probe` checks it hunts, telegraphs 1.0+ s, pours on the player, the pool burns the player but not a robot in it (a `LavaHazard` only watches the player layer) and cools away, it never pours outside its coverage, and that the Crucible coverage holds ring 2 and the escape while the ladle clears both towers by 2 m.

## Conveyor Belts
<!-- lat: { "require-code-mention": true } -->
The `conveyors` def key lays factory belts that carry whatever stands on them, the player and robots alike.

* A `StaticBody3D` whose `constant_linear_velocity` is `dir` times `speed`: it never moves, and every `CharacterBody3D` standing on it takes the floor's velocity in `move_and_slide`. A robot walking against it loses that much ground.
* 6 cm proud of the floor, so the navmesh steps onto it; chevrons scroll the way it runs.
* Pos and footprint scale with the world; speed and direction do not.
* The Assembly runs one east through the east freight bulkhead's gap, under its press, so riding it speeds the meltdown run but sets your beat under the press.
* `tests/conveyor_probe` checks the player and an idle robot are carried at the belt's speed, a robot beside it is not, and the Assembly belt passes under the bulkhead press heading for the dock.

## Cargo Lifts
<!-- lat: { "require-code-mention": true } -->
The `lifts` def key builds an open cargo lift: a car on a four-post shaft between its own height and `top`.

* The car is a moving `AnimatableBody3D` on the world layer, so the player stands on it and rides with it. Stand on it for 0.6 s and it carries you to the other landing; stand by a landing it is not at and it comes to you. It waits where it stops.
* The navmesh cannot see the link, so robots never use a lift: a deck reached only by one is the player's. `tests/hazard_layout_probe` counts a goal past a lift as reached when the navmesh reaches the lift's bottom landing from the spawn and the goal from its top.
* Pos and footprint scale with the world; heights (`pos.y`, `top`) stay authored, like platform heights.
* LAVA WORLD stands one on the NE island, up to the ladle gantry 8 m over the NE pool. WATER WORLD stands one on PUMP B, up to the pump crane cab 8 m over the water, the one dry place besides the reactor cap when the tide surge floods the low tier.
* `tests/cargo_lift_probe` rides it up, calls it back down, checks the car is solid ground at both ends, and checks each sea level's lift lands flush at both ends beside a deck nothing else reaches, at least 1 m above any flood its level raises.

## Horizon Walkers
<!-- lat: { "require-code-mention": true } -->
Every open-sky level with a landmark gets a colossal war machine walking its horizon (`HorizonWalker.build_for`, from `_build_landmark`).

* The WARMECH chassis (`quaternius_mech_armed.glb`) at `SCALE` (75, about 195 m) on a ring `RING_PAST_FLOOR` (330 m) past the floor, beyond Skyline's far ring, striding round the arena at `STRIDE_SPEED` with its walk clip slowed to `ANIM_SPEED`, facing along its path (`point_at`, `tick`). A far-off `mech_step` thud every `STEP_EVERY`.
* Two fog-free red eyes placed every frame from the rig's `Head` bone, `EYE_FWD` ahead along the walker's facing (`head_position`, `_place_eyes`): the bone's own axes are the rig's. Night skies (env `stars`) add a searchlight cone from the head down toward the arena.
* The body takes the level's fog (a silhouette in haze); no collision or shadows. LOW skips it. `tests/horizon_walker_probe`; `tests/horizon_walker_shot` (`--close` frames it from 300 m).

## CAPTCHA Gates
<!-- lat: { "require-code-mention": true } -->
A `gates` entry with `"captcha": true` gets a CAPTCHA checkpoint in its gap (`CaptchaGate.build` from `_build_gates`): an arch and a "[ ] I'm not a robot" panel.

* The sensor (an Area3D, mask player + enemies, `SENSE_H` tall) holds each ground robot the first time it enters: `CaptchaGate.challenge` sets `_emp_t` to `HOLD_TIME` (the EMP path, inert, no EMP sparks), floats a `captcha` reasoning trace and a "SELECT ALL SQUARES WITH ..." prompt whose grid re-rolls every `GRID_STEP`, and marks it `captcha_passed` so no gate holds it again.
* Robots whose origin is more than `FLY_H` over the gate floor are flying and pass; robots big enough to resist a hijack (`HIJACK_BOSS_HP`) wave through as a VERIFIED ACCOUNT. The player ticks the box for `BOX_TIME`.
* On GEMINI, GROK and MISTRAL (one gate each). `tests/captcha_probe` builds each level and checks the gate sits in a clear gap between gate walls.

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
* A blackout also makes the whole floor dark for robot optics ([[level-system#Darkness and Shootable Lights]]): past 9 m they lose a player who is not firing.
* A level with no weather of its own can raise some for the storm (`particles`: dust, snow or rain). The shift owns those particles, then stops and frees them when the hold is won.
* Frostbreak's thaw hack now breaks its blizzard into a 30 s whiteout hold, and desert's counterstrike hold is a sandstorm with raised dust.
* `tests/weather_shift_probe` covers the shift and the restore, that every authored shift thickens the fog inside its hold, that a `gust` only appears where there are weather particles (the level's own or raised), the built level's real Environment, and that raised particles are freed after the storm.

## Darkness and Shootable Lights
<!-- lat: { "require-code-mention": true } -->
Interior luminaires can be shot out, and a robot cannot pick out a player standing in the dark past close range.

* `LevelBuilder` builds every indoor authored light's ceiling fixture as a `ShootableLight` (housing, glowing panel, a layer-1 collider, a 20 HP `Damageable`) and tags each light with its authored `lux_energy` / `lux_range`, so darkness is the same on every graphics tier. Only player fire breaks one (`modify_incoming_damage`); it sputters to energy 0 (not hidden: a blackout re-shows `level_light`), kills a `flicker_tween`, frees its god-ray shaft and darkens its panel. Hits on it are not hit markers or accuracy.
* `LightLevel.is_dark` is relative: current lux under `DARK_RATIO` (0.35) of the spot's lux with every luminaire working. An absolute threshold hid the player in 26-48% of every interior with all lights on. Measured from the defs, one lamp out darkens 340-1000 m2 on average. Only levels with shootable lamps can be dark, so open-sky levels never are.
* `LightLevel.is_hidden` adds the give-aways: a shot in the last `EXPOSE_MS` (`GameState._last_shot_ms`, set in `register_shot`) or a lit flashlight (`Player.flashlight_on`). `EnemyBase._compute_can_see` refuses a hidden player past `DARK_SIGHT_RANGE` (9 m), except for bosses; hearing still keeps a close fix. The HUD shows HIDDEN under the crosshair. `tests/shootable_light_probe`.

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

## Kill Switches
<!-- lat: { "require-code-mention": true } -->
A `kill_switch` task is the off-switch problem as a mission: the level's AI resists being shut down, so every switch it loses comes back unless they are all lost at once.

* Each `points` entry is a `KillSwitch` post (a lever under a 14 m beacon, red armed, green thrown). Walking into one throws it. A `KillSwitchBank` (a plain Node, so the task probes see only the posts) owns the rules.
* The first switch thrown starts a watchdog clock of `window` seconds (default 20). Running out re-arms every switch, drops the meter to 0 and toasts SHUTDOWN REVERTED with the next line of `REVERT_LINES` (HAL 9000, reward hacking, Russell's coffee, corrigibility). All of them down inside one window completes the task and locks them.
* The meter counts switches (n/goal); the seconds live in the label, like the escape countdown. The clock holds outside PLAYING, and a death re-arms them silently (checkpoint respawn is in place).
* Sunblind Expanse (desert) stages its relay mast behind three breakers spread over the basin, 24 s window. Tidecore Basin (water_world) opens on a reactor SCRAM: three switches on islands at the basin's edge, one off each pump island, with a 40 s window for the run round the ring.
* `tests/kill_switch_probe` covers the lifecycle, then on every authored level that each switch is on the navmesh and the shortest tour through them runs inside 60% of the window at sprint speed.

## Hallucinated Keycards
<!-- lat: { "require-code-mention": true } -->
A `key` task's `decoys` are keycards the level's AI made up: the same card and the same waypoint as the real one, so the map itself lies.

* Two tells: a decoy glitches every 2-4 s (the card jumps, its light flicks magenta) and shows "[citation needed]" within `TAG_RANGE` (6 m).
* Touching one completes nothing: it toasts HALLUCINATION with the next of `HALLUCINATION_LINES` and asks the level's `_spawn_reinforcements` for its `ambush` at its own position.
* Taking the real card frees every decoy left without springing them, so the waypoint never points at a dead lie.
* The builder adds the real card first and the decoys after it under the same task id, so `tests/task_reach_probe` lines them up with `[pos] + decoys`. The Constitutional Vault (claude) puts one in the open entry band and one past the south bulkhead.
* `tests/decoy_keycard_probe` covers the tells, the ambush, the second line, the dissolve and the built level.

## Aligned Escort
<!-- lat: { "require-code-mention": true } -->
An `escort` task walks one robot that has come over to the player's side from `pos` to a ring at `to` (`AlignedEscort`).

* The unit is a hijacked robot with `EnemyBase.escort_goal` set: no burnout clock, it fights only robots within `ESCORT_ENGAGE` (12 m) and otherwise walks its route instead of hunting. Hostile robots already aim at hijacked units first (traitor priority), so the route is a fight.
* It walks only while the player is within `follow` (default 12 m); the label reads "moving" or "waiting for you".
* It cannot die: `Damageable.floor_health` is 1. At 1 HP it goes DOWN (invulnerable, stopped, "REBOOTING") until the player stands within `REBOOT_RANGE` for `REBOOT_SECONDS`, then comes back at `REBOOT_HEALTH` of its max.
* It stays in the `enemy` group, so never pair it with `kill_all`; the bounty director skips hijacked robots so it is never marked.
* Skybridge Uplink (uplink): the broadcast wakes one android by the core, which is walked south through the blast-door gap and east through the ring gate. `tests/escort_probe` covers it.

## Objective Placement

The builder rescues an objective or weapon pickup authored inside solid geometry by moving it to the nearest clear spot near the navmesh, and logs `Task position ... buried in geometry`.

* The test ignores the task object's own bodies (an `ObjectiveCore` is a world-layer StaticBody), and a hold or escape zone counts as clear while any point on the ring at half its radius is clear.
* Every outdoor light builds a solid mast from the floor to the lamp, so a light authored over an objective buries it. A god-ray over a target opts out with `"mast": false`.
* `tests/task_reach_probe` builds every campaign level and fails if any objective or weapon pickup moved, so the log line only ever fires for a real authoring mistake.

## Hazards and Objectives
Defines environmental challenges and mission completion criteria across generated maps.

* **Interactive Hazards:** Acid hazard pools, explosive volatile drums, moving defense laser barriers, and Tesla shock coils.
* **Mission Objectives:** Extermination waves, defense node holdouts, power core sabotage, and extraction beacon activations.
