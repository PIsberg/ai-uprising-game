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
* **Permanent Upgrades:** Weapon tuning tiers (recoil compensation, clip extensions, faster reload, damage amplification) and stamina upgrades.
* **Consumable Supplies:** Field supplies (medical nanites, reserve ammo packs, extra starting grenades) purchasable for immediate deployment on the next level.

## 3D Enemy Codex
<!-- lat: { "require-code-mention": true } -->
The enemy codex (`scripts/ui/enemy_codex.gd`) provides a comprehensive intelligence database on the rogue AI forces:
* **Discovery Unlocks:** Entries unlock dynamically as players encounter each hostile unit in campaign or custom missions via `GameState.mark_enemy_seen`.
* **Interactive 3D Inspector:** Features interactive 3D model rotation, zoom, wireframe view, and animation playback.
* **Combat Intelligence:** Details armor thickness, critical headshot zones, behavioral states, weapon types, and recommended counter-weapons.

## Weapon Codex
<!-- lat: { "require-code-mention": true } -->
The weapon codex (`scripts/ui/weapon_codex.gd`) documents the full arsenal available to the human resistance:
* **Arsenal Roster:** Covers 17 wieldable weapons spanning kinetic firearms, energy beam platforms, and heavy ordinance.
* **Comparative Statistics:** Normalized comparative bar graphs for raw DPS, effective range, fire rate, recoil severity, and handling.
* **Firing Profiles:** Explains primary hitscan/projectile dynamics, alt-fire charge cycles, and special mechanics (piercing, splash, chain lightning, homing).
