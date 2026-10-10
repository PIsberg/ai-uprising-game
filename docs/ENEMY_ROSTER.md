# Enemy Roster — subclass audit

All 45 combat enemies extend `EnemyBase` (`scripts/enemies/enemy_base.gd`), a CharacterBody3D
state machine (IDLE/PATROL/ALERT/CHASE/ATTACK/STAGGER/DEAD) with a `Damageable` child (`hp`).
(`enemy_bomb.gd` is excluded: it is a lobbed bomb projectile extending `Node3D`, not an enemy.)

Two base-class conventions make the flags in this table matter:

1. **Stats are hardcoded in `_ready`.** Every subclass writes its real `max_health` /
   `move_speed` / `attack_cooldown` in its own `_ready` (by convention after
   `super._ready()`). Elite affixes and campaign difficulty therefore must never write
   stats directly — they stack `_health_mult` / `_speed_mult` / `_cooldown_mult`, which
   `_sync_stats` re-applies **deferred** so it lands after the subclass body has run.
   Writing stats pre-`add_child` gets clobbered; `Elite.apply` / `apply_nemesis` must run
   before `add_child`.
2. **Overriding `_on_died` / `_state_attack` without `super` silently drops base logic.**
   This is the repo's most recurring bug class (barks, bounty payoff, loot, kill credit,
   codex discovery have all been bitten by it). 7 subclasses override `_on_died` and 11
   override `_state_attack` without calling super — so any **new** base-class death or
   attack feature must hook the `hp.died` / `hp.damaged` signals instead of extending
   those methods (see the `mark_bounty` / `_on_died_voice` pattern in `enemy_base.gd`).
   The one deliberate exception is the weapon kill style (`KillFx`): it lives in the base
   `_on_died` because it *replaces* the base death visuals. Of the 7 overrides, DRONE (and
   its children), RAPTOR, MENDER and SKITTER read it themselves through
   `_kill_style()` / `_prep_kill_fx()`; SEEKER keeps its shot-down blast (that blast is a
   mechanic) and the bosses ARCHON and OVERSEER keep their deaths.

Column notes: "Overrides w/o super" lists only overrides that do **not** call
`super._on_died(...)` / `super._state_attack(...)` / `super(...)` — an override that calls
super is safe and not listed. A `†` on the script means its `_ready` sets stats **before**
calling `super._ready()` (deviates from the documented order; functionally harmless today,
because base `_ready` reads the already-set vars and `_sync_stats` is deferred past the whole
`_ready` chain either way — but keep new base `_ready` logic order-insensitive). Scripts that
extend an intermediate class (`EnemyDrone`, `EnemyAndroid`, `EnemyDog`, `EnemyColossus`)
inherit that parent's overrides too.

| Enemy | Script | Model | Role / Signature | Overrides w/o super | Boss |
|---|---|---|---|---|---|
| ALIEN | `enemy_alien.gd` † | imported animated creature (RobotModel on `$Model`) | aerial strafer; charged fanned bio-plasma volley + screaming dive | `_state_attack` | — |
| ANDROID | `enemy_android.gd` | imported model on `$Model` (scene) | hitscan burst skirmisher; flanks, sidestep jukes | `_state_attack` | — |
| ARCHON | `enemy_archon.gd` | fully procedural (code-built holographic brain + shield) | finale boss: invulnerable shield while minion waves live, briefly exposes core | `_on_died` | BOSS |
| BOWLER ("STRIKER-9") | `enemy_bowler.gd` | repainted brute chassis (scene) | stationary artillery pitcher; hurls homing molten orbs, close-range shove | — | — |
| BREAKER | `enemy_breaker.gd` (extends EnemyDrone) | drone chassis (inherited) | pure melee flyer; hovers, dives to hammer-slam, drifts back out | (drone's) | — |
| BRUTE | `enemy_brute.gd` | imported "Mike" heavy mech (`$Model` in scene) | shielded tank; frontal shield blocks 90%, telegraphed windup slam — flank it | — | — |
| COLOSSUS ("GOLIATH-IX") | `enemy_colossus.gd` | imported "George" heavy mech | 3-phase mega-boss: rocket artillery, sweeping chest beam, seismic slams; sky-drop entrance | `_state_attack` | BOSS |
| DIFFUSION | `enemy_diffusion.gd` (extends EnemyAndroid) | `quaternius_gunner_armed.glb` (the armed bot, unused since STRIDER merged into GUNNER), violet tint | burst rifleman that, every `DIFFUSE_EVERY` s in a fight, noises out (dissolve shader in pure-noise mode, off the enemy layer, no damage), crosses as a static cloud to a flank `pick_destination` found (floor, navmesh, no hazard, headroom, LOS to the target) and denoises there over `DENOISE_TIME` taking x`HALF_FORMED_MULT`; overrides `_on_died` (calls super, restores its materials first) and `_play_hit_flash` (calls super only when formed) | (android's) | - |
| QUANTIZER | `enemy_quantizer.gd` (extends EnemyDrone) | `quaternius_flyergun_armed.glb` (the armed flying gun, unused until now), green tint | flying gunner (the drone's projectile kit) whose precision drops with health (`STAGE_AT` 0.75/0.5/0.25 -> FP16/INT8/INT4, off hp.damaged, never back): every chassis surface swaps once to `shaders/quantize.gdshader` (world-space vertex snap `STAGE_GRID`, posterize `STAGE_LEVELS`) via `KillFx.swap_to_dissolve(..., SHADER)`; overrides `attack_interval` (x`STAGE_CD`) and `aim_spread_deg` (+`STAGE_SPREAD`); overrides `_on_died` (calls super, hides the tag) | (drone's) | - |
| ROLLBACK | `enemy_rollback.gd` (extends EnemyAndroid) | `quaternius_mech.glb` (the unarmed mech, unused until now), pale cyan tint | unarmed support that hangs back (`preferred_range` 20) and listens on the `hp.died` of every robot within `WATCH_RANGE`; a death leaves a checkpoint (scene, spot, facing, difficulty mults) unless it was a DISINTEGRATE kill, a boss, a FORK BOMB or an already-restored robot; every `RESTORE_GAP` it channels `CHANNEL_TIME` on the freshest checkpoint (beam, `shaders/vhs_rewind.gdshader` column, timecode) and restores a fresh instance that rebuilds through `KillFx.swap_to_dissolve` off the enemy layer for `REBUILD_TIME`; `INTERRUPT_DMG` mid-channel, EMP, hijack or its death cancel; `RESTORES_MAX` 3; overrides `_start_burst` (no gun) | (android's) | - |
| REWARD MODEL | `enemy_reward.gd` (extends EnemyDrone) | `quaternius_flyergun.glb` (the base flying gun, unforked), white-gold tint | non-shooting support flyer that hangs back: when a robot within 20 m hurts the player (player Damageable `damaged`), it beams that robot a reward (attack_cooldown x0.8 per stack, max 3, one per 0.8 s, gold "REWARD +n" tag); bosses never; its death revokes every reward | (drone's) | — |
| MIXTURE OF EXPERTS | `enemy_moe.gd` (extends EnemyAndroid) | `quaternius_bot.glb` (the unarmed base bot), ice-blue tint, + four orbiting expert pods (AnimatableBody3D on the enemy layer, 60 HP Damageable each) | router: every 3.2 s in a fight it routes to one live expert, which sets its burst (SNIPER 1x20 tight, SCATTER 6x4 wide, SHIELD x0.3 damage taken + slow, SPRINT x1.8 speed); shots come from the active pod; hologram shows the routing; shot-off pods are gone for good; all four gone -> ROUTER COLLAPSED, x1.5 damage taken | (android's) | — |
| ATTENTION HEAD | `enemy_attention.gd` (extends EnemyDrone) + `scripts/systems/attention.gd` | `Enemy_EyeDrone.gltf` at 2x, gold tint | non-shooting spotter: a lagging gaze cone (9 deg, 38 m, `shaders/gaze_cone.gdshader` + SpotLight3D); while it is on the player with a clear line, `Attention` tightens every robot's `scatter_aim` to x0.45, idle robots within 40 m wake onto the player and engaged ones are fed the player's position; unalerted it sweeps the floor like a searchlight; EMP/hijack/death put the gaze out | (drone's) | — |
| OVERFITTER | `enemy_overfitter.gd` (extends EnemyAndroid) | `quaternius_gunner.glb` (the base GUNNER chassis, unforked), training-green tint, green eye | burst rifleman that learns the gun hurting it (`Damageable.hit_weapon`): after 90 damage from one gun it is OVERFIT (that gun x0.25, a fresnel-grid shell in the gun's tracer colour, hologram "OVERFIT: <gun>"); any other gun breaks it: OUT OF DISTRIBUTION, x1.5 from everything for 3 s, learns nothing meanwhile. Untagged damage (grenades, hazards, melee) is never resisted or learned | (android's) | — |
| DEEPFAKE | `enemy_deepfake.gd` (extends EnemyAndroid) + `deepfake_decoy.gd` | `quaternius_bot_armed.glb`, violet tint, magenta eye | burst rifleman that projects two copies of itself (`DeepfakeDecoy`, not in the `enemy` group: no kill_all, radar, homing, score or accuracy) which mirror its moves and fire harmless tracers with it; swaps places with a copy half the time; copies glitch and cast no shadow, pop in one hit, collapse when it dies | (android's) | — |
| DOG ("K-9 HUNTER") | `enemy_dog.gd` † | `assets/models/robots/robot_dog.glb` | fast pack hound; telegraphed rear-back pounce into bite | — | — |
| DRONE | `enemy_drone.gd` | recon-flyer chassis (scene); base for Whirlwind/Shark/Breaker/Fishbot | basic ranged flyer; hover-strafe, dives; falls and explodes on death | `_on_died`, `_state_attack` | — |
| ENFORCER | `enemy_enforcer.gd` (extends EnemyAndroid) | android chassis (inherited) | armored trooper; ranged bursts + telegraphed green suppression-laser sweep | (android's) | — |
| FISHBOT ("ANGLER UNIT") | `enemy_fishbot.gd` (extends EnemyDrone) | drone chassis + code-built fins/bubble trail | fast fragile hit-and-run swimmer; spits water bolts | (drone's) | — |
| FORK BOMB | `enemy_forkbomb.gd` (extends EnemySpider) | Trilobite crawler, acid-green tint, scaled 1.25 / 0.9 / 0.62 by generation | spider's dart-and-pounce melee; killed, forks into two smaller faster copies (via `hp.died`), which fork once more: 1 -> 2 -> 4; a disintegrating kill deletes it before it forks | (spider's) | — |
| GUNNER | `enemy_gunner.gd` | `quaternius_gunner_siege.glb` (Blender fork of Quaternius "Robot Enemy Large Gun": recoil spades, gun shield, ammo drum, rotary mount) + code-built barrel cluster on the Gun bone | tanky suppressor; telegraphed spin-up into 12-round burst (the barrels really spin up through the windup and glow hotter per round), plants while firing | — | — |
| GUNSLINGER | `enemy_gunslinger.gd` (extends EnemyAndroid) | android chassis (inherited) | duelist; single heavy slugs on slow cadence, sidestep weave | (android's) | — |
| HIVE | `enemy_hive.gd` † | `quaternius_bot_hive.glb` (Blender fork: uplink mast, dish, relay pack, shield-emitter prongs) + procedural shield mesh + mast-tip link beacon | networked flanker; energy shield until inside a jammer zone (beacon goes dark with it), spreads flank angles across siblings | — | — |
| HOWITZER | `enemy_howitzer.gd` | `assets/models/robots/walking_robot_gun.glb` | slow four-legged artillery walker; charged ballistic splash shells | — | — |
| HUNTER | `enemy_hunter.gd` † | "quaternius_gunner_bladed" chassis (scene) | circle-strafe skirmisher; bolt bursts + blade-dash gap-closer | — | — |
| MANUS | `enemy_manus.gd` | `assets/models/robots/robot_arm_wip_2.glb` | rooted giant-arm boss: sweep/slam/grab-hurl/finger spikes; single weak-spot core; finger-drum entrance; 3 HP-keyed phases (cooldowns ×1/0.8/0.62, phase 3 double finger eruption leading the player) — `tests/manus_phase_probe` | `_state_attack` | BOSS |
| MAULER | `enemy_mauler.gd` † | real robot model in `mauler.tscn` (RobotModel Punch clip) | heavy melee brawler; OVERLOAD at 35% HP — sprint + timed self-detonation | — | — |
| MECH | `enemy_mech.gd` | imported model on `$Model` (scene) | heavy charger; telegraphed stomp shockwave up close, splash rockets at range | `_state_attack` | — |
| MENDER | `enemy_mender.gd` | EyeDrone chassis, tinted teal (scene) | support flyer; beam-heals most-wounded ally, flees the player, never attacks | `_on_died` | — |
| OPTIC ("OPTICON") | `enemy_optic.gd` (extends EnemyAndroid) | android chassis (inherited) | charged sweeping cutting beam + android burst rifle filler (both overrides call super) | (android's) | — |
| ORB ("MOLTEN ORB") | `enemy_orb.gd` (extends EnemyDog) | `assets/models/robots/robot_ball.glb` | rolling crusher sphere; bounce-charges, ruptures into magma AoE on death (calls super) | — | — |
| OVERSEER | `enemy_overseer.gd` | giant imported EyeDrone (`$Model` in scene) | hovering gunship boss: escalating volleys + rocket barrage, spawns Seekers in phase 3; portal entrance | `_on_died` | BOSS |
| RAPTOR | `enemy_raptor.gd` | `quaternius_flyergun_strike.glb` (Blender fork of Quaternius "Robot Enemy Flying Gun": swept wings, engine nacelles, V tail, beak, belly gun pod, talons) | flying gunner; hover-strafe bursts + a committed stoop: dives along a locked line raking belly-gun bolts ahead, talon rake (14) at the bottom, climbs out guns quiet; nose follows the flight path, thrusters vector hover/run | `_on_died`, `_state_attack` | — |
| RAVAGER | `enemy_ravager.gd` † | bladed fierce chassis, scaled up (scene) | telegraphed high-arc leap into AoE ground-slam; melee swipes between leaps | — | — |
| REAPER | `enemy_reaper.gd` † | real robot model in `reaper.tscn` | fast hovering melee killer; glides in, lunges into a slashing strike | — | — |
| RIPPER | `enemy_ripper.gd` (extends EnemyAndroid) | `robot_minigun.glb` | minigun platform; spin-up telegraph, walking saw stream that trails the player (calls super) | (android's) | — |
| ROLLER | `enemy_roller.gd` (extends EnemyDog) | scene model | grounded ram; plant/spin tell then straight-line charge into bite + knockback | — | — |
| RONIN | `enemy_ronin.gd` | `assets/models/robots/robot-killer_model.glb` | revolver slugs at range, flanking dash, two-cut katana combo up close | — | — |
| SEEKER | `enemy_seeker.gd` † | EyeDrone chassis + code-built fins/warning band | kamikaze flyer; locks on and detonates on contact, blinking-core telegraph | `_on_died`, `_state_attack` | — |
| SENTINEL | `enemy_sentinel.gd` † | "quaternius_heavy" chassis via `sentinel.tscn` | planted heavy weapons platform; bolt volleys, every Nth a 3-shell mortar salvo | — | — |
| SERVER ("MAITRE-D'") | `enemy_server.gd` † | `assets/models/robots/serving_bot.glb` | slow tanky basher; spinning thrown cleavers at range, knockback tray-bash up close | — | — |
| SHARK ("RAZORFIN") | `enemy_shark.gd` (extends EnemyDrone) | scene model | submerged stalker; cruises underwater, breaches in an arc to bite | `_state_attack` (+ drone's) | — |
| SKITTER | `enemy_skitter.gd` | trilobite crawler, tinted red (scene) | swarm chaff; fast scuttle, brief windup, ballistic pounce-bite; lean custom death | `_on_died` | — |
| SMASHER ("BEHEMOTH-X") | `enemy_smasher.gd` | "rusty_claws_robot" via RobotModel (auto-fit 10 m) | melee boss: overhead smash, ground-slam AoE, claw-rake lunge; molten wake-slam entrance; attack cooldowns ×1/0.8/0.62 by phase (`boss_phase_probe`) | `_state_attack` | BOSS |
| SNIPER | `enemy_sniper.gd` † | RobotModel on `$Model` (scene) | stationary long-range hitscan; visible charged-beam telegraph, stagger interrupts the charge | — | — |
| SPIDER | `enemy_spider.gd` | trilobite crawler (scene) | fast melee harasser; dart-freeze-dart cadence, telegraphed leap-pounce bite | — | — |
| TERMINATOR ("APEX ENDOFRAME") | `enemy_terminator.gd` | Quaternius "Animated Robot" GLB (rigged, animated) | fast mobile ranged boss: dual-muzzle bursts + tracking sweeping "Optic Lance" beam; floor-eruption entrance | `_state_attack` | BOSS |
| TITAN ("PROMETHEUS-0") | `enemy_titan.gd` (extends EnemyColossus) | "Giant Robot" (Dann Beeson, CC-BY) | boss: phase-gated spatial-fold teleport-blink flanks + charged sweeping beam; overrides `_begin_entrance` (violet rift) | (colossus's; own `_choose_attack` calls super) | BOSS |
| VACUUM ("Custodian") | `enemy_vacuum.gd` † | fully procedural (code-built disc chassis + legs) | disguised idle floor-cleaner; rises into a walker on detection, fires energy bolts | — | — |
| WARBOT | `enemy_warbot.gd` (extends EnemyAndroid) | android chassis + code-built arm cannons/face | twin arm-cannon rifleman; mood face, rage-mode burst below 45% HP | (android's) | — |
| WARMECH | `enemy_warmech.gd` | Quaternius Mech, twin shoulder cannons | heavy siege walker; long charged telegraph into 3-shell plasma salvo, plants while firing | — | — |
| WHIRLWIND | `enemy_whirlwind.gd` (extends EnemyDrone) | scene model (spins `Model/Mesh`) | hovering buzzsaw; dives to melee-slash at close range, no ranged attack | (drone's) | — |

**Boss entrances:** `_begin_entrance` is defined on `EnemyColossus` and overridden by
`EnemyTitan`; the other bosses stage their own bespoke entrances (SMASHER wake-slam,
TERMINATOR floor eruption, MANUS finger-drum, OVERSEER/ARCHON `BossPortal`), all announcing
via `GameState.announce_boss`.

**Tallies:** 45 subclasses. `_on_died` overridden without super: **7** (ARCHON, DRONE,
MENDER, OVERSEER, RAPTOR, SEEKER, SKITTER — matches the "seven subclasses" comment in
`enemy_base.gd`). `_state_attack` overridden without super: **11** (ALIEN, ANDROID,
COLOSSUS, DRONE, MANUS, MECH, RAPTOR, SEEKER, SHARK, SMASHER, TERMINATOR). Overrides that
correctly call super: `_on_died` — COLOSSUS, MANUS, OPTIC, ORB, SMASHER, TERMINATOR;
`_state_attack` — OPTIC, RIPPER. `†` (stats set before `super._ready()`): 12 scripts.

## Maintenance

Adding a new enemy, a new `_on_died` / `_state_attack` override, or changing an override's
super-call behavior? Update this table (and remember: base-class death/attack features hook
`hp.died` / `hp.damaged`, never those two methods).
