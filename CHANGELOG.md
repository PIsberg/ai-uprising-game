# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Added an "OUT OF GRENADES" message that appears when trying to throw a grenade with an empty inventory.
- The Manus Boss's weak spot (core) now has collision, allowing it to correctly take damage.
- New headless probes covering the fixes below, all wired into `tools/run_tests.sh`: `damage_source_probe`, `seeker_grace_probe`, `blast_direction_probe`.
- `spawn_safety_probe` — sweeps all 24 campaign levels checking that an idle player takes no damage during the opening-seconds grace, and reports each level's post-grace incoming damage as a difficulty readout.

### Changed
- Headshots are now more difficult to achieve, requiring greater precision.
- Fixed an issue where the factory default Melee key (F) would steal the keybind back on restart if the user had assigned F to Zoom (or another action).
- Taking aggressive actions (like a Melee shove or a Dash) now cleanly breaks you out of Aiming Down Sights (ADS) for a smoother transition, instead of keeping the camera zoomed in while the weapon model punches out of frame.
- Changed the damage hit-flash on enemies to white, preventing them from appearing golden/red when taking rapid damage.
- Optimized 3D assets to load faster and consume less memory, resulting in a smoother gameplay experience.

### Fixed
- Shots and explosions whose owner was destroyed before the hit landed dealt **no damage at all** — the hit was silently discarded. This fired constantly in a firefight, since a robot dying while its shot is still in the air is routine.
- The SEEKER kamikaze drone ignored the opening-seconds grace that follows a level load or respawn. It could fly in and detonate on you for around a fifth of your health before you had a chance to move. It now holds the blast until the grace ends, then still detonates — deferred, not defused.
- A BRUTE's frontal shield judged explosions by where *you* were standing rather than where the blast actually went off, so a grenade thrown behind one was still blocked at 90%. Flanking a shield with explosives now works as intended: a blast from behind lands roughly 19x the damage of one from the front.
- Repaired two long-broken checks in the test suite (`victory_probe`, `convoy_probe`) and added them to CI. Neither was a game bug: `victory_probe` sampled one frame too early and caught the loading screen mid-handoff on the way to the victory cutscene, and `convoy_probe` demanded a fixed kill count from the convoy demo charge, which varies with whichever pursuit wave happens to be alive.
- Fixed the defect behind every intermittent CI failure we have on record. `survival_probe` and `gun_range_probe` timed their bots and measurements on wall-clock, while everything they measure — enemy attack cadence, weapon bloom, first-shot accuracy, recoil settle — advances on the game clock. On a machine that cannot hold the physics rate the two drift apart, so both probes were quietly measuring the wrong thing in proportion to how loaded the machine was. Every CI failure across a 30-run stretch was this one defect.
- `pacing_sweep`, the cross-level difficulty instrument, did not wait for each level to tear down before loading the next, so every reading after the first death described the *previous* level's already-dead player.
