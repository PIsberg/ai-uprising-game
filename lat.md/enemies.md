# Enemy State Machines and Roster

Enemies in the game inherit from a base CharacterBody3D and follow state-driven behaviors.

## Enemy Base State Machine
<!-- lat: { "require-code-mention": true } -->
The class `EnemyBase` (`scripts/enemies/enemy_base.gd`) implements a finite state machine:
* **States:** `IDLE`, `PATROL`, `ALERT`, `CHASE`, `ATTACK`, `STAGGER`, `DEAD`
* A `Damageable` node child manages enemy health, armor, and death callbacks.

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
