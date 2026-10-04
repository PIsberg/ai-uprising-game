# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- **Security firewalls** (`firewalls` level-def key): an energy sheet that stops only the player (new collision layer 8), dropped by shooting its relay node or by completing a linked objective. Placed on claude, gemini and mistral, so the server aisle, the shielded conduit and the exit bulkheads become things you open rather than walk through. `firewall_probe` (suite), `firewall_shot` (windowed).
- **Vision scanners** (`scanners` level-def key): sweeping surveillance heads that call in a reinforcement squad when they hold the player in their beam for 0.7 s, at most twice each. Shoot the head to blind one. Skyhold Command (overseer) gets three: the north landing ring, the east exit corridor, and a full-circle command eye on the spire. `scanner_probe` (suite), `scanner_shot` (windowed).
- **Escape countdown** (`escape` task type): the last stage of a level can be a timed run to an extraction ring; once the clock runs out the purge burns the player until they get there. The remaining seconds show in the objective line. `escape_probe` (suite).
- **xAI Black-Site (grok)**: the mainframe now trips a 40 s site purge. You run out through the east bulkhead, past a kill team that drops into the corridor, to extraction. A watchtower scanner crowns the climbable tower over the monolith field, and a second one stares up the exit corridor; both throw cold cyan beams across the crimson site. The level no longer ends on kill-all.
- **Skybridge Uplink**: re-graded from one flat blue (hue entropy 0.48, the lowest of the levels measured) to a signal-storm night, with a magenta horizon, a teal milky way, sodium-amber lamps around the antenna field and the uplink core kept cyan (entropy 1.11). The roofed east shutter into the relay yard is now firewalled from a relay up on the broadcast gallery: climb up and shoot it, or take the sky-bridge high road over the wall.
- **First Contact (The Hollow)**: no longer a green fog soup. The sky, fog, ambient light and sun were all green, so the haze tinted every surface the same colour (hue entropy 0.88, contrast std 0.14). It's now a violet-black alien night: green lives in the milky-way band, the bioluminescent accents and the field lamps, and two ring lamps take the beacon's violet. Hue entropy 1.81.

- **Haul payloads** (`haul` task type): a heavy core that has to be carried on foot to an uplink ring. While carrying, you walk at 72% speed with no sprint, dash or grapple; 30 HP of hits knocks it a few metres behind you, and dying drops it where you fell. The HUD waypoint switches between the core and the ring. `haul_probe` (suite).
- **Anthropic Constitutional Vault**: a third act. After the decrypt, the constitution is a heavy core you carry 51 m out through the archive firewall to an uplink by the exit, with the decrypt's sentinels on you.

### Fixed
- mistral's west coolant pump was authored inside the divider wall; moved 2 m clear so it can be stood on.

## [2026.09.21] - 2026-09-21

### Added
- **Dedicated enemy models & combat profiles**:
  - **HIVE**: Custom uplink mast model (`quaternius_bot_hive.glb`) with relay pack, yagi uplink mast, dish, whip antenna, and pulsating link beacon that clearly shows networked vs. jammed state (`hive_uplink_probe`).
  - **GUNNER**: Planted rotary siege cannon model (`quaternius_gunner_siege.glb`) featuring spin-up acceleration, barrel heat, and overheat cooldown periods (`gunner_siege_probe`).
  - **RAPTOR**: Aerodynamic flyer strike model (`quaternius_flyergun_strike.glb`) executing predatory high-speed stoop dives (`raptor_stoop_probe`).
- **Tidecore Basin (`water_world`) Layout**: Distinct catwalk gantry network, reactor cap exit climb, and pump islands separating it from `lava_world` (`hazard_layout_probe`).
- **Sublevel & Overseer mission arcs**: Multi-stage combat and objective progression for sublevel and overseer levels (`mission_arc_probe`).
- **Campaign Escalation**: Escalating wave hold sequences across campaign survive objectives (`survive_waves_probe`).
- **Architecture Lattice (`lat.md`)**: Full referential integrity checks and section backlinks integrated with `lat check`.
- The Damage Taken accessibility assist now counts toward the level grade the way a difficulty tier does (x0.85 at 50%, x1.10 at 150%) and is named on the debrief next to the tier. `grade_assist_probe` (suite).
- `opening_distance_check` treats a triggered enemy whose trigger radius already contains the spawn as awake from the start; that was the shape of every idle-DPS spike.

### Fixed
- Level loading subthread race condition resolved, ensuring clean headless and exported boots without level 1 hangs.
- Added CI concurrency cancellation to prevent simultaneous redundant builds from exhausting runner minutes.

### Fixed
- Spawn-camping packs on claude, gemini, lava_world and water_world: squadmates placed 5–12 m from the spawn with trigger radii that already contained it warped in and rushed an idle player the moment the opening grace lapsed. Moved or re-radiused so the player has to step toward them: idle post-grace damage (`spawn_safety_probe`) water_world 84 → 22/s, lava_world 44 → 9/s, claude 41 → 0/s, gemini 35 → 0/s.
- Two authored enemy spawns sat inside geometry (crucible tower, lava_world lamp post) and were being nudged by the spawner on every load.
- The three heaviest robot models carried 2K PBR maps for chassis that fill a few hundred pixels; embedded images downscaled to 1K in place with `tools/glb_shrink.py` (scene graph untouched), 66 MB → 28 MB and 41 MB → 32 MB on disk. `rusty_claws_robot` was 57 MB of mesh instead: decimated to 35% in headless Blender (`tools/blender/decimate.py`, 950k → 333k triangles, 58 MB → 25 MB), every node and material name preserved.
- Added an "OUT OF GRENADES" message that appears when trying to throw a grenade with an empty inventory.
- The Manus Boss's weak spot (core) now has collision, allowing it to correctly take damage.
- New headless probes covering the fixes below, all wired into `tools/run_tests.sh`: `damage_source_probe`, `seeker_grace_probe`, `blast_direction_probe`.
- `spawn_safety_probe` — sweeps all 24 campaign levels checking that an idle player takes no damage during the opening-seconds grace, and reports each level's post-grace incoming damage as a difficulty readout.
- `aim_hit_probe` — verifies that aiming at a robot actually damages it: every weapon against a reference enemy at 6/18/35m, and every one of the 43 enemies against the rifle. All 11 weapons and all 43 enemies pass.
- `opening_distance_check` — reports how much room each level gives you at spawn, measured as the distance to the nearest enemy that is awake from the start.

### Changed
- Headshots are now more difficult to achieve, requiring greater precision.
- Fixed an issue where the factory default Melee key (F) would steal the keybind back on restart if the user had assigned F to Zoom (or another action).
- Taking aggressive actions (like a Melee shove or a Dash) now cleanly breaks you out of Aiming Down Sights (ADS) for a smoother transition, instead of keeping the camera zoomed in while the weapon model punches out of frame.
- Changed the damage hit-flash on enemies to white, preventing them from appearing golden/red when taking rapid damage.
- Optimized 3D assets to load faster and consume less memory, resulting in a smoother gameplay experience.
- The two hazard levels (flooded reactor, molten sea) opened with an enemy 9.8m from your spawn, against a campaign-wide norm of 32m or more — they were the only two levels below that floor. Those units were moved out to match, and the second fast flyer on each now wakes as you advance rather than at the start. Note this does NOT resolve the wider difficulty spike on those two levels (see below); it removes the point-blank opening only.

### Fixed
- Shots and explosions whose owner was destroyed before the hit landed dealt **no damage at all** — the hit was silently discarded. This fired constantly in a firefight, since a robot dying while its shot is still in the air is routine.
- The SEEKER kamikaze drone ignored the opening-seconds grace that follows a level load or respawn. It could fly in and detonate on you for around a fifth of your health before you had a chance to move. It now holds the blast until the grace ends, then still detonates — deferred, not defused.
- A BRUTE's frontal shield judged explosions by where *you* were standing rather than where the blast actually went off, so a grenade thrown behind one was still blocked at 90%. Flanking a shield with explosives now works as intended: a blast from behind lands roughly 19x the damage of one from the front.
- Repaired two long-broken checks in the test suite (`victory_probe`, `convoy_probe`) and added them to CI. Neither was a game bug: `victory_probe` sampled one frame too early and caught the loading screen mid-handoff on the way to the victory cutscene, and `convoy_probe` demanded a fixed kill count from the convoy demo charge, which varies with whichever pursuit wave happens to be alive.
- Fixed the defect behind every intermittent CI failure we have on record. `survival_probe` and `gun_range_probe` timed their bots and measurements on wall-clock, while everything they measure — enemy attack cadence, weapon bloom, first-shot accuracy, recoil settle — advances on the game clock. On a machine that cannot hold the physics rate the two drift apart, so both probes were quietly measuring the wrong thing in proportion to how loaded the machine was. Every CI failure across a 30-run stretch was this one defect.
- `pacing_sweep`, the cross-level difficulty instrument, did not wait for each level to tear down before loading the next, so every reading after the first death described the *previous* level's already-dead player.
- Two ammo pickups on the alien level sat inside solid cover. A pickup is collected by walking into it, and you cannot walk into a solid block, so they could never be picked up. Six props on other levels were likewise buried inside walls — invisible, while still carving navmesh where they stood. The eight authored positions were corrected, and the layout check that catches this now runs in CI.
- The demo charge on the convoy ride is no longer judged by a fixed kill count in testing — how many robots die depends on which pursuit wave is alive, so the check now verifies the blast actually reaches everything inside its radius. Its zipline checks also waited a fixed real-time delay that could expire mid-winch on a slow machine.

### Known issues
- The flooded-reactor and molten-sea levels still deal heavy damage to a stationary player (measured 77/s and 50/s with no input). The root cause is that neither level has any safe standing ground: the flooded reactor's water covers the entire arena, and the molten sea's spawn and exit both sit inside lava pools, so you start and finish standing in the hazard. Moving the spawn clear drops the figure from 61/s to 4.5/s, but the only lava-free ground on that level is outside the baked navmesh — the levels need walkway geometry, which the hazard's own "get back onto the walkway" warning already assumes exists. Tracked in issue #61.
