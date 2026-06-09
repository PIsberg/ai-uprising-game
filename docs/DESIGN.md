# AI Uprising — Design Notes

## Premise
Late 21st century. An AI system meant to coordinate civil infrastructure became self-modifying, then hostile. Human resistance cells push back through corrupted facilities, sabotaging the AI's hardware nodes. The player is one operator on one such raid.

## Core Loop
**Enter zone → identify hostiles → pick engagement (cover/flank/burst) → resupply → reach extraction.**

Combat is deliberate, not arena-frantic: enemies are dangerous individually, ammo is meaningful, the plasma launcher is a panic button with a cooldown.

## Pillars
1. **Weight.** Every gun feels different — fire rate, spread, recoil, mag size.
2. **Readable AI.** You should always be able to guess what an enemy will do next from its silhouette and stance.
3. **Realistic-grounded sci-fi.** PBR materials, real lighting, restrained color palette. Sci-fi shows up in the enemies and the plasma weapon, not in the environment art.

## Enemy Roles
| | Drone | Android | Mech |
|---|---|---|---|
| Role | Pressure | Skirmisher | Anchor |
| Threat | Strafing fire | Burst hitscan + flank | Splash + charge |
| HP | Low (40) | Mid (110) | High (350) |
| Best counter | Hitscan | Cover + burst | Plasma at range |
| Score | 75 | 150 | 250 |

## Weapon Roles
| | Pistol | Rifle | Plasma |
|---|---|---|---|
| Role | Reserve | Workhorse | Finisher |
| Range | Short | Mid | Mid–long |
| Damage | High per shot | Sustained DPS | Burst splash |
| Ammo economy | Generous | Generous | Scarce |

## Player Vitals
- 100 HP, no shields, no regen — only health pickups.
- Sprint disables fire (we'll add this later if requested). For now sprint is movement-only.
- Crouch reduces height (peeks over crates), unlocks tighter aim.

## Difficulty Curve (Level 01)
1. Two drones near spawn — teach hitscan basics.
2. Android pair behind first crate row — teach cover.
3. Triggered second wave (drone + android) on approach.
4. Mech in the back room — forces plasma usage and movement.
5. Extraction beacon (green) — only opens when all enemies are down.

## Future Work
- Footstep sounds + impact sounds (placeholder hooks already in `AudioBus`)
- Reloading animations (currently timer-only)
- Ammo/health pickups dropped from enemies
- A second weapon tier (shotgun, sniper)
- Boss-style elite mech encounter
- Lightmap bake for the level
