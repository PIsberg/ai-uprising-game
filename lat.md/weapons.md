# Weapons and Physics Layers

This document outlines the design and integration of the weapon systems and physics collision configurations.

## Weapon Manager
<!-- lat: { "require-code-mention": true } -->
The `WeaponManager` resides under the player's camera:
* Resolves the list of active weapons from player inventories.
* Automatically sorts weapon instances from weakest to strongest.
* Spawns projectile nodes and handles hitscan raycasting.

## Weapon Resources
Defines the custom resource configuration files that govern weapon attributes.

* Individual weapon stats are defined via `WeaponData` resource files (`.tres` and `scripts/weapons/weapon_data.gd`) located under `assets/weapons/` across 17 distinct weapons.
* Modifications to ammo capacity, reload speed, damage, and projectile patterns should be edited in these resource files.

## Weapon Mods
<!-- lat: { "require-code-mention": true } -->
Bought in the Armory, a mod changes what a gun's hit does, not how hard it lands. One mod per hitscan or beam gun, refitted for free.

* `GameState.MOD_DEFS`, `owned_mods`, `weapon_mods` (scene path -> mod id), saved with the run and cleared by `start_campaign`. `BASE_LOADOUT` must match `player.tscn`'s rack (`tests/weapon_mods_probe` checks).
* `WeaponMods` runs the effect from `Weapon._do_hitscan` and `_update_beam`: CHAIN ARC (35% to the nearest robot within 7 m), THERMITE (30% of every hit over 3 s, six ticks; one burn per robot that each hit adds to and restarts, ticks ignore armour), RICOCHET (a wall hit bounces 60% into a robot within 15 m and 35 degrees of the reflection), OVERRIDE (a hit leaving a non-boss below 25% hijacks it for 6 s, 8 s cooldown per gun).
* ARC and RICOCHET proc at most once per 120 ms per gun, so shotgun pellets and beam ticks draw one arc or bounce. The limit thins the effect, not the damage: `WeaponMods._bank` holds the hits in between and the next proc carries them, so a fast gun gets its full share. THERMITE is not limited.
* `tests/mod_value_probe` (headless report) measures each mod's damage per gun against an unarmoured and an armour-4 pack.
* Proc damage goes through `GameState.apply_secondary_damage`, which pays score, leech and OVERLOAD charge but is not a new hit for accuracy or the AI Director. Breakable-cover shrapnel uses it too.
* `WeaponMods` and `GameState.mod_compatible` duck-type robots and weapons: naming `EnemyBase` or `Weapon` there closes a load cycle through the pickup scenes and `pickup.gd` fails to load.

## Kill Styles
<!-- lat: { "require-code-mention": true } -->
The weapon that lands the killing blow picks how a robot dies (`WeaponData.kill_fx`, `scripts/fx/kill_fx.gd`).

* DISINTEGRATE (gauss, Longshot, plasma, OMEGA): the robot's materials swap to `shaders/dissolve.gdshader`, which burns it away top-down in 1 s behind a glowing edge; no wreck. ELECTROCUTE (tesla, arc coil, tempest): 0.75 s of spasms under arcs and a blue skin, then the classic blast (`EnemyBase._classic_death_fx`). SHRED (Breacher shotgun, .50 magnum): `KillFx.shred` throws the robot 3.2 m away from the shooter (`EnemyBase._shot_dir`) in a tumbling arc with a scrap spray, a world ray cutting the flight short of walls, then the classic blast where it lands.
* The style rides on `Damageable.kill_fx` only for the duration of the weapon's `apply_damage` call (`KillFx.tag` / `untag`). `died` fires inside that call, so `_on_died` sees the killing hit's style and nothing else: grenades and hazards never tag.
* Bosses keep their deaths. Overrides of `_on_died` opt in through `EnemyBase._kill_style()` / `_prep_kill_fx()`: drones and raptors burn away mid-air or spasm before they fall, menders and skitters split like the base. A SHRED kill knocks drones and raptors along the shot as they fall (`EnemyBase._shred_kick`). The seeker keeps its shot-down blast, a mechanic. `tests/kill_fx_probe`.

## Grenades
Defines the physics layers and player-bound scripts for throwing grenades.

* Unlike standard firearm classes, Grenades live directly on the player script (`grenade_kinds` in `scripts/player/player.gd`) and are mapped to physics layer 8.
* Four grenade types are supported: FRAG, VORTEX (singularity gravity-well), EMP (disables robot firmware), and HIJACK (converts robot loyalty).
* Grenade actions are mapped to `grenade` (throw, `G`) and `grenade_cycle` (cycle types, `H`).

## Collision Mask Configuration
<!-- lat: { "require-code-mention": true } -->
Collision layers determine raycast and physics interaction target filtering:
* **Enemy Hitscans & Line of Sight:** Raycast masks target Layer 1 (World) and Layer 2 (Player).
* **Player Projectiles & Fire:** Raycast masks target Layer 1 (World) and Layer 4 (Enemies).
