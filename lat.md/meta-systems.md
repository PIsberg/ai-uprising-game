# Meta Progression and Codex Systems

This document describes the out-of-mission systems: the campaign progression route, the armory upgrade shop, and the 3D codex archives.

## Campaign Map
<!-- lat: { "require-code-mention": true } -->
The campaign map interface (`scripts/ui/campaign_map.gd`) renders an interactive holographic sector map:
* **Progression Route:** Serpentine mission nodes tracing the human resistance path toward the central AI core.
* **Sector Intel:** Displays hostile unit compositions, primary/secondary objectives, environmental hazard ratings, and boss encounters before deployment.
* **Navigation & State:** Supports mouse, keyboard, and controller navigation; synchronizes completed sectors and unlocked routes with `GameState.CAMPAIGN`.

## Armory Shop
<!-- lat: { "require-code-mention": true } -->
The Armory (`scripts/ui/armory.gd`) provides a meta-progression shop between combat missions:
* **Score Economy:** Converts player mission score and bounty rewards into credits for persistent equipment investments.
* **Permanent Upgrades:** Six run-long tracks (`Armory.KEYS`): `damage`, `mag` (clip size), `reload`, `blast` (grenade radius), `leech` (heal from damage dealt) and `stamina`.
* **Consumable Supplies:** Three supply keys (`Armory.SKEYS`): `ammo`, `grenades` and `health` (max HP on deploy). These persist for the whole run and are re-applied on every deploy.
* **Weapon Mods:** Four cards (`Armory.MKEYS`) with a gun picker: BUY + FIT buys a mod and fits it to the picked gun; owned mods FIT or SWAP for free. See [[weapons#Weapon Mods]].

## Daily Op
<!-- lat: { "require-code-mention": true } -->
One seeded level a day, outside the campaign (main menu, under Last Stand):
* **Seed:** `GameState.daily_op_for(date)` hashes the local date, so every player gets the same op on the same day: one non-boss campaign level other than the first, and one directive (always rolled).
* **Loadout:** HARD, with `GameState.daily_arsenal(level)`, the guns the campaign hands out before that level (weapon pacing); no Armory upgrades or mods.
* **Isolation:** `start_daily_op` snapshots the run state (`DAILY_RUN_KEYS`); while `daily_op` is set, `load_level` skips the campaign bookkeeping and `save_progress` refuses to write. `end_daily_op` (called by the main menu on every visit) restores the snapshot, so no path out of an op leaves its difficulty or guns behind.
* **Records:** `record_daily_clear` keeps the day's best score and a streak of consecutive days with a clear in `records.cfg` `[daily]`; the win screen shows score, best and streak and returns to the menu (`advance_level` -> `finish_daily_op`). `tests/daily_op_probe` (suite).

## 3D Enemy Codex
<!-- lat: { "require-code-mention": true } -->
The roster data lives in `scripts/systems/enemy_codex.gd` (`EnemyCodex.ENTRIES`, ordered by
`EnemyCodex.ORDER`); the bestiary screen that renders it is `scripts/ui/encyclopedia.gd`:
* **Discovery Unlocks:** Entries unlock as the player meets each hostile unit; `EnemyBase` calls `GameState.mark_enemy_seen`, and `GameState.has_seen_enemy` gates the entry. Undiscovered robots stay classified.
* **Live 3D Model:** Each entry instantiates the robot's real scene on a turntable that spins slowly on its own (`_turntable`, 0.5 rad/s). There is no zoom, wireframe or animation-playback control.
* **Entry Fields:** An entry carries only what the screen shows: `scene`, display `name`, `desc` dossier line, and the `scale`/`y`/`yaw` framing values that pose the model.

## Weapon Codex
<!-- lat: { "require-code-mention": true } -->
The weapon codex (`scripts/ui/weapon_codex.gd`) documents the full arsenal available to the human resistance:
* **Arsenal Roster:** Covers the 13 wieldable weapons in `GameState.WEAPON_ORDER` (weakest to strongest, pistol through OMEGA-X), spanning kinetic firearms, energy beam platforms, and heavy ordnance. Only weapons the player has held appear, plus the `STANDARD_ISSUE` trio.
* **Comparative Statistics:** Normalized comparative bar graphs for raw DPS, effective range, fire rate, recoil severity, and handling.
* **Firing Profiles:** Explains primary hitscan/projectile dynamics, alt-fire charge cycles, and special mechanics (piercing, splash, chain lightning, homing).
