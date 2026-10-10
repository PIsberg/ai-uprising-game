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
* **Hijacking:** When an enemy is hijacked, they switch from Layer 4 to Layer 2 and target other enemies. Damage calculation blocks enemy-to-enemy damage unless their hijack alliances differ.
* **Phantoms:** during the MODEL HALLUCINATION event, `PlayerPhantom` decoys sit on Layer 2 in group `player_phantom` (never `player`). `EnemyBase._perceive` retargets a robot onto a phantom nearer than its current target, by the same distance rule as the hijacked-traitor priority.

## Elite Affixes
<!-- lat: { "require-code-mention": true } -->
The elite system (`scripts/systems/elite.gd`) upgrades standard hostile units into formidable variants with distinct combat twists:
* **SHIELDED:** Heavy armor plating, amplified health pool, flat damage reduction, cold blue tint.
* **VOLATILE:** High-explosive core that detonates violently upon unit destruction, damaging surrounding enemies and the player.
* **SWIFT:** Accelerated movement speed, faster attack animations, and shortened reaction delays with a bright teal glow.
* **WARDEN:** Immune to stagger and poise interrupts; forces tactical dodging rather than suppression fire.
* **SPLITTER:** Splits into two active `Skitter` swarmers upon fatal damage, punishing blind cluster clearing.

Each elite carries a spinning marker above its head whose SHAPE names the affix (`MARKER_SHAPES`): a sphere for SHIELDED, a spike for VOLATILE, a double-cone diamond for SWIFT, a pillar for WARDEN and a block split in two for SPLITTER. Colour (`AFFIX_COLORS`) is only the second cue, so the marker still reads for colourblind players.

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
