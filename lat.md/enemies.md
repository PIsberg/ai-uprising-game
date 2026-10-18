# Enemy State Machines and Roster

Enemies in the game inherit from a base CharacterBody3D and follow state-driven behaviors.

## Enemy Base State Machine
<!-- lat: { "require-code-mention": true } -->
The class `EnemyBase` (`scripts/enemies/enemy_base.gd`) implements a finite state machine:
* **States:** `IDLE`, `PATROL`, `ALERT`, `CHASE`, `ATTACK`, `STAGGER`, `DEAD`
* A `Damageable` node child manages enemy health, armor, and death callbacks.

## Reasoning Traces
<!-- lat: { "require-code-mention": true } -->
Robots float a short `<think>` line over their heads on real decisions: first contact, wounded, cover retreat, EMP, hijack, panic.

`EnemyBase._think` measures head clearance once; `ReasoningTrace.think` throttles (global gap, per-robot gap, on screen within RANGE, the Combat Callouts setting). New decision points call `_think(kind)` with a `LINES` key. `tests/reasoning_trace_probe`.

## Head Tracking
<!-- lat: { "require-code-mention": true } -->
Skinned robots turn their head (and spine) toward their target on top of the playing clip, so they visibly watch the player instead of staring along their body's facing.

* `RobotModel._build_head_track` mounts a `HeadTrackModifier` (a `SkeletonModifier3D`) on any rig where `HeadTrackModifier.chain_for` finds a head bone; `chain_for` adds the torso/chest/spine/neck bones that are ancestors of the head, 0.18 of the turn each, the head the rest.
* `RobotModel._update_look` eases a (pitch, yaw) look in the BODY's frame toward the target (`aim_height`: a player's eyes, a robot's chest) while ALERT/CHASE/ATTACK and not EMP'd, back to zero otherwise, clamped to `MAX_YAW_DEG` / `MAX_PITCH_UP_DEG` / `MAX_PITCH_DOWN_DEG`, and turns the modifier off at rest and on death. The modifier carries that rotation into skeleton space and splits it as powers of one quaternion, so it works whatever axis a rig's bones use.
* Skeleton3D restores the clip pose after modifiers run: read a modified bone pose inside `skeleton_updated`. `tests/head_track_probe`.
* Gun arms (#232): `EnemyBase.muzzle_on_bone` registers its bone through `add_gun_bone` -> `RobotModel.add_gun` -> `HeadTrackModifier.add_gun` (mounting the modifier on head-less rigs too, the SNIPER). After the head turn, `_aim_arm` swings the arm's pivot (`arm_root_for`: the first bone below the look chain or the body, skipping a `Shoulder` clavicle) so pivot -> muzzle passes through `aim_point`, by `arm_weight` (eased by `_update_look`), at most `MAX_ARM_DEG`. Throwers pass `aim = false` (BOWLER, SENTINEL); twin guns aim from between their barrels.
* Because the clip pose comes back after drawing, the modifier keeps every muzzle bone's drawn pose (`rendered_pose`) and `EnemyBase.bone_point` reads it, so shots leave the barrel where it is drawn. `tests/arm_aim_probe`.

## Physics Wrecks
<!-- lat: { "require-code-mention": true } -->
A dead robot's wreck is thrown by physics, so it goes off a catwalk edge, slides down a ramp and drops out of the air instead of toppling in place.

* `EnemyBase._classic_death_fx` launches a `WreckBody` (`scripts/fx/wreck_body.gd`), a RigidBody3D box the chassis' size on layer 0 / mask 1 (it never blocks the player), with velocities set directly (an impulse x mass on the first tick flung it 370 m): `PUSH` along the shot, `LIFT`, a `TIP` about up x dir. The robot stays in its place in the tree (levels watch it); the body writes the robot's transform each tick and carries the wreck fire upright. It settles after `SETTLE_TIME` (or asleep after `MIN_TIME`), then `_sink_wreck` sinks it. A skinned rig also gets a `LimpLimbsModifier` (`scripts/meshes/limp_limbs_modifier.gd`): its limb bones lag the tumbling chassis and hang toward gravity on a damped spring, inside a 75 deg cone of the frozen pose and above the floor under them. It is a secondary-motion ragdoll, not `PhysicalBone3D`: the rigs' 41-270x import scales break physical bones.
* Bosses (score >= 1000) keep the scripted topple their kill-cam frames. Not per-bone ragdolls: the skinned rigs are 41-270x scaled and `PhysicalBone3D` loses that scale (#259). `tests/wreck_physics_probe`.

## Death Log
<!-- lat: { "require-code-mention": true } -->
A robot's death types its last log line over the wreck (`scripts/fx/death_log.gd`); the Reasoning Traces show what it decides, this shows how it ends.

* `DeathLog.log_death` runs from `EnemyBase._death_log` on `hp.died` (not `_on_died`, which subclasses override without super), at the body top + 0.25 m. It rolls `chance` (`CHANCE`, 0.45), waits out `GAP_MS` since the last line, and needs the spot on screen within `RANGE`; Combat Callouts off silences it. Bosses (score >= 1000) skip the roll and the gap, reach twice as far, and always print `BOSS_LINE`.
* The Label3D goes under the robot's parent, not the robot, because the wreck is freed under it: types out, rises `RISE`, fades, frees itself (group `death_log`). `tests/death_log_probe`.

## Health and Subclass Scaling
<!-- lat: { "require-code-mention": true } -->
To prevent scaling values from being overwritten, subclasses must:
1. Define base/initial values in `_ready` **after** calling `super._ready()`.
2. Apply modifications (difficulty, elite scaling) using multipliers: `_health_mult`, `_speed_mult`, and `_cooldown_mult` deferred via `_sync_stats`.
3. Avoid modifying basic properties directly before node initialization.

## Collisions and Hijacking
Defines collision filtering rules and hijack-behavior mechanics.

* **Collision Layers:**
  * Layer 1: World geometry.
  * Layer 2: Player collision.
  * Layer 4: Enemy collision.
* **Hijacking:** When an enemy is hijacked, they switch from Layer 4 to Layer 2 and target other enemies. Damage calculation blocks enemy-to-enemy damage unless their hijack alliances differ. A hijacked unit with `escort_goal` set (an escort task's ALIGNED unit) never burns out and walks its route instead of hunting.
* **Phantoms:** during the MODEL HALLUCINATION event, `PlayerPhantom` decoys sit on Layer 2 in group `player_phantom` (never `player`). `EnemyBase._perceive` retargets a robot onto a phantom nearer than its current target, by the same distance rule as the hijacked-traitor priority.
* **Mislabeling:** `EnemyBase.mislabel(duration)` (an adversarial patch slapped onto a robot) moves it to Layer 2 and the `mislabeled` group with a red HUMAN tag. `_perceive` treats a mislabeled robot like a hijacked one, and `Damageable.apply_damage` lets its own squad's fire land on it. Whoever applied it owns the clock and calls `clear_mislabel`, because a timer in EnemyBase would never tick on subclasses that skip `super._physics_process`.

## Elite Affixes
<!-- lat: { "require-code-mention": true } -->
The elite system (`scripts/systems/elite.gd`) upgrades standard hostile units into formidable variants with distinct combat twists:
* **SHIELDED:** Heavy armor plating, amplified health pool, flat damage reduction, cold blue tint.
* **VOLATILE:** High-explosive core that detonates violently upon unit destruction, damaging surrounding enemies and the player.
* **SWIFT:** Accelerated movement speed, faster attack animations, and shortened reaction delays with a bright teal glow.
* **WARDEN:** Immune to stagger and poise interrupts; forces tactical dodging rather than suppression fire.
* **SPLITTER:** Splits into two active `Skitter` swarmers upon fatal damage, punishing blind cluster clearing.
* **RETURNER:** A `GrenadeReturner` child catches a player frag (`Grenade`, not `hostile`) within `CATCH_RANGE` in its line of sight with more than `MIN_FUSE` left, holds it for `WINDUP`, then lobs a `hostile` charge (`hit_mask` world + player) that sticks where it lands. Damage or death during the wind-up fumbles: the player's own charge, with its original blast, drops at its feet. The director's counter to a frag habit (`AIDirector.frag_habit`, fed by `note_frag`). `tests/returner_probe`.

Each elite carries a spinning marker above its head whose SHAPE names the affix (`MARKER_SHAPES`): a sphere for SHIELDED, a spike for VOLATILE, a double-cone diamond for SWIFT, a pillar for WARDEN, a block split in two for SPLITTER and an upright ring for RETURNER. Colour (`AFFIX_COLORS`) is only the second cue, so the marker still reads for colourblind players.

## Nemesis System
<!-- lat: { "require-code-mention": true } -->
A persistent nemesis mechanic creates high-stakes grudge matches across campaign runs:
* **Promotion:** Elite units that kill the player can be promoted to Nemesis rank (`Elite.apply_nemesis`).
* **Visual & Combat Cues:** Marked by furnace-red glow, scaled model size (+10%), increased health/speed multipliers, and custom kill-feed alerts.
* **Settling Grudges:** Eliminating a Nemesis awards double score value, guaranteed supply drop rewards, and logs progression via `GameState.nemesis_slain`.

## Archetype Roster
Categorizes the rogue AI combat units into distinct tactical roles.

* **Swarms & Minions:** `Skitter`, `Spider`, `Drone` — rapid, low-health harassment units that flank or overwhelm. `Forkbomb` replicates on death (two copies per generation, `MAX_GEN` 2) unless a disintegrating kill deletes it first.
* **Frontline & Heavies:** `Brute`, `Ravager`, `Warmech`, `Smasher` — heavily armored pressure units with shields, cleaves, and ground slams.
* **Ranged & Support:** `Sniper`, `Howitzer`, `Mender`, `Optic` — long-range artillery, beam chargers, and unit repair specialists.
* **Deception:** `Deepfake` — projects two `DeepfakeDecoy` copies that mirror its moves and fire harmless tracers with it. Copies stay out of the `enemy` group, so kill_all, radar, homing, score and accuracy all ignore them; they pop in one hit and collapse when it dies. `Overfitter` learns the gun hurting it from `Damageable.hit_weapon` (set with the kill style by `KillFx.tag`): after `FIT_DAMAGE` from one gun that gun does a quarter damage; a different gun breaks the fit and opens a 3 s window of +50% from everything, during which it learns nothing. `Attention` (ATTENTION HEAD) never shoots: its lagging gaze cone on the player calls `Attention.hold()`, which tightens every robot's `scatter_aim` (x`ATTENDED_SPREAD`), wakes idle robots within `ALERT_RADIUS` and feeds engaged ones the player's position; the static state lives outside EnemyBase so the base never names a subclass. `MoE` (MIXTURE OF EXPERTS) routes, every `ROUTE_TIME`, to one live expert pod that rewrites its burst stats (SNIPER/SCATTER/SHIELD/SPRINT; SHIELD via `modify_incoming_damage`); the pods are their own enemy-layer targets, and losing all four collapses the router (`COLLAPSE_MULT`). `Reward` (REWARD MODEL) listens on the player's Damageable `damaged` signal and rewards the robot that hurt the player (`attack_cooldown` x`REWARD_CD`, base kept in meta `reward_base_cd`); `revoke_all` on its death restores every one. `Diffusion` runs its forward process as a flank: `diffuse_to` swaps its surfaces onto the dissolve shader in pure-noise mode (saving the originals), drops off the enemy layer and takes nothing while it noises out and crosses as a static cloud, then denoises at a point `pick_destination` checked for floor, navmesh, hazards, headroom and a line to the target, taking `HALF_FORMED_MULT` until it is whole. `Rollback` keeps checkpoints of robots that die near it (through their `hp.died`, reading the kill style during the emission, so a disintegrating kill leaves none) and channels a restore that spawns a fresh copy of the dead robot's scene on its difficulty multipliers, rebuilt feet-first with `KillFx.swap_to_dissolve` / `restore_dissolve` (the same reversible swap DIFFUSION uses); damage, EMP or hijack mid-channel corrupts the checkpoint, and a restored robot is marked `restored` so it never comes back twice. `Quantizer` loses precision with health (`stage_for`, off `hp.damaged`, lossy: healing never restores it): the first drop swaps its surfaces onto `shaders/quantize.gdshader` through `KillFx.swap_to_dissolve`'s `shader` argument, each stage sets the `grid` and `levels` instance uniforms, and `attack_interval` / `aim_spread_deg` overrides trade aim for cadence.
* **Overlords & Bosses:** `Colossus`, `Manus`, `Titan`, `Archon` — multi-phase autonomous war machines with unique attack patterns and stagger resistance.

## Telemetry Leech
<!-- lat: { "require-code-mention": true } -->
`EnemyLeech` is a gunless flyer whose threat is information: latched on, it tells the rest of the level where the player is.

* It weaves in at head height and calls `latch` within `LATCH_RANGE`, never during `attack_grace_active`, through dash i-frames (`Damageable.invulnerable`) or while stunned. Latched, it sits at `BACK_OFFSET` behind the camera with `collision_layer` 0, so it cannot be shot.
* Latched: `DRAIN_DPS`, the player's speed times `SLOW` (`Player._current_speed` checks the `leech_latched` group), and a `_beacon` every `BEACON_PERIOD` that sets every idle or patrolling robot within `BEACON_RANGE` onto the player (`State.ALERT`).
* `Player._handle_melee` calls `rip_off` (killed); a dash start calls `shake_off` (detached, flung, `emp_disable(SHAKE_STUN)`), after which it hunts again.
* Sublevel: two, in the west service ring and the east yard. `tests/leech_probe`.

## AEGIS Shield Drone
<!-- lat: { "require-code-mention": true } -->
`EnemyAegis` extends `EnemyMender` and reuses its support loop through hooks (`support_color`, `_support_stale`, `_pick_support_target`, `_support`, `_support_lost`); the MENDER's own behaviour is unchanged (`tests/mender_probe`).

* Its target is the ally nearest the player, skipping support drones, hijacked units and boss-class robots (`HIJACK_BOSS_HP`).
* While the beam holds, `Damageable.warded_by` points at it: `apply_damage` returns before any damage and calls `on_ward_hit` (bubble flash, one-time hint). The ward is cleared when the target changes, the beam breaks, or the AEGIS dies or leaves the tree.
* Skybridge Uplink: one rides in with the survive hold's second wave; Desert (Relay 7): one with the counterstrike's armour wave. `tests/aegis_probe`.
