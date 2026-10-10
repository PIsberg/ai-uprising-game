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
* **Deception:** `Deepfake` — projects two `DeepfakeDecoy` copies that mirror its moves and fire harmless tracers with it. Copies stay out of the `enemy` group, so kill_all, radar, homing, score and accuracy all ignore them; they pop in one hit and collapse when it dies. `Overfitter` learns the gun hurting it from `Damageable.hit_weapon` (set with the kill style by `KillFx.tag`): after `FIT_DAMAGE` from one gun that gun does a quarter damage; a different gun breaks the fit and opens a 3 s window of +50% from everything, during which it learns nothing. `Attention` (ATTENTION HEAD) never shoots: its lagging gaze cone on the player calls `Attention.hold()`, which tightens every robot's `scatter_aim` (x`ATTENDED_SPREAD`), wakes idle robots within `ALERT_RADIUS` and feeds engaged ones the player's position; the static state lives outside EnemyBase so the base never names a subclass. `MoE` (MIXTURE OF EXPERTS) routes, every `ROUTE_TIME`, to one live expert pod that rewrites its burst stats (SNIPER/SCATTER/SHIELD/SPRINT; SHIELD via `modify_incoming_damage`); the pods are their own enemy-layer targets, and losing all four collapses the router (`COLLAPSE_MULT`).
* **Overlords & Bosses:** `Colossus`, `Manus`, `Titan`, `Archon` — multi-phase autonomous war machines with unique attack patterns and stagger resistance.
