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
