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

* DISINTEGRATE (gauss, Longshot, plasma, OMEGA): the robot's materials swap to `shaders/dissolve.gdshader`, which burns it away top-down in 1 s behind a glowing edge; no wreck. ELECTROCUTE (tesla, arc coil, tempest): 0.75 s of spasms under arcs and a blue skin, then the classic blast (`EnemyBase._classic_death_fx`). SHRED (Breacher shotgun, .50 magnum): `KillFx.shred` throws the robot 3.2 m away from the shooter (`EnemyBase._shot_dir`) in a tumbling arc with a scrap spray, a world ray cutting the flight short of walls, then the classic blast where it lands. DECAPITATE: tagged by `Weapon._do_hitscan` itself (not WeaponData) on a headshot from a gun with `kill_fx` 0 (pistol, rifle); `EnemyBase._decapitate` folds the head bone (`_head_bone`), flings a head chunk with its eye lit, fountains the neck (`KillFx.neck_fountain`) and rocks the chassis back for `DECAP_TIME` before the classic blast. No head bone, or a drone/raptor: the ordinary death. BLAST (Devastator, Swarm Launcher): `EnemyBase._blast_apart` tears up to `BLAST_LIMBS` limbs and the head off at once (`_dismember_limb(..., force)` past `LIMB_LOSS_MAX`), lofts the torso `BLAST_LIFT` m through two chain-reaction pops over `BLAST_TIME`, then the classic blast; drones and raptors detonate mid-air.
* The style rides on `Damageable.kill_fx` only for the duration of the weapon's `apply_damage` call (`KillFx.tag` / `untag`). `died` fires inside that call, so `_on_died` sees the killing hit's style and nothing else: grenades and hazards never tag.
* Bosses keep their deaths. Overrides of `_on_died` opt in through `EnemyBase._kill_style()` / `_prep_kill_fx()`: drones and raptors burn away mid-air or spasm before they fall, menders and skitters split like the base. A SHRED kill knocks drones and raptors along the shot as they fall (`EnemyBase._shred_kick`). The seeker keeps its shot-down blast, a mechanic. `tests/kill_fx_probe`.

## Data Bleed
<!-- lat: { "require-code-mention": true } -->
Robots bleed binary when hit and pour it out when they die (`scripts/fx/data_bleed.gd`).

* `DataBleed.spill` runs from `Weapon._enemy_hit_pop` on every hitscan hit on a robot (`hit_amount`: `HIT_MIN`..`HIT_MAX` by damage, +`CRIT_BONUS` on a crit), thrown back toward the shooter; walls never spill. At most `FRAME_BUDGET` spills start per physics frame (shotgun pellets).
* `DataBleed.burst` runs from `EnemyBase._data_burst`, on `hp.died` rather than in `_on_died`, so subclasses that override `_on_died` without super still burst: `BURST_AMOUNT` glyphs rising from mid-body. It ignores the frame budget.
* One CPUParticles3D per spill, freeing itself on `finished`; a two-frame sheet ("0" | "1", `glyph_texture()` drawn from 5x7 bitmaps) picked per particle by `anim_offset`. Unshaded, `disable_fog`, no shadows; LOW halves the amounts. `tests/data_bleed_probe`.

## Rail Trail
<!-- lat: { "require-code-mention": true } -->
Railgun rounds ionize the air they cross (`scripts/fx/rail_trail.gd`, `WeaponData.rail_trail`: the gauss and the Longshot).

* `Weapon._do_hitscan` calls `RailTrail.spawn` from the muzzle to where the round stopped, in `shot_color()` (so a RAMPAGE tier tints it). The trail starts `START` past the muzzle and keeps at most `MAX_LEN`; at most `MAX_LIVE` live at once, the oldest freed first.
* One ArrayMesh per shot (`build_mesh`): a helix band `PITCH` metres a turn at `RADIUS` (vertex `NORMAL` points out from the axis, `COLOR.a` 0) round two crossed core quads (`COLOR.a` 1). `shaders/rail_trail.gdshader` animates it from the `age` instance uniform over `LIFE`: the coil swells, wobbles and rises like smoke as it fades, the core burns out in the first half. Additive, fog-free, shadowless; LOW uses fewer segments a turn. `tests/rail_trail_probe`.

## Rampage Charge
The gun charges up with the RAMPAGE kill streak (`Weapon._on_rampage_changed`, on `GameState.rampage_changed`).

* At tier n, `Weapon.shot_color()` returns `GameState.RAMPAGE_COLORS[n - 1]` (the HUD banner's palette, one source): tracers and the muzzle flash take it, and the flash grows `RAMPAGE_FLASH_GROW` per tier.
* Every viewmodel mesh outside the muzzle subtree (`rim_meshes()`) wears `assets/materials/rampage_rim.tres` (`shaders/rampage_rim.gdshader`, a pulsing fresnel rim) as `material_overlay`; tier 0 takes it off. `tests/weapon_rampage_probe`.

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
