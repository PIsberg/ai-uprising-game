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
