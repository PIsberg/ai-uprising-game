# Player Systems and Locomotion

This document specifies the player character mechanics, movement physics, stamina constraints, tactical abilities, and camera feel in **ai-uprising-game**.

## Locomotion and Stances
<!-- lat: { "require-code-mention": true } -->
The player controller (`scripts/player/player.gd`) implements a responsive First-Person CharacterBody3D:
* **Movement Speeds:** Authorised walk (`5.5 m/s`), sprint (`9.0 m/s`), and crouch (`2.8 m/s`) velocities with snappy acceleration (`18.0`) and friction (`14.0`).
* **Jump Mechanics:** Includes standard jump (`7.5 m/s`), coyote time (`0.1s`), jump buffering (`0.12s`), and a sprint-jump momentum boost (`1.3x`) charged by continuous running.
* **Toggle vs Hold:** with Settings' Toggle Aim / Toggle Sprint / Toggle Crouch on (`GraphicsSettings.toggle_*`, pushed to `PlayerInput.toggled`), `PlayerInput.pressed` latches the action on at one press and off at the next, per player; `_handle_movement` calls `input.release("sprint")` when there is no move input, and the HUD reads aim through the player's input (`hud.aim_held`) so the crosshair follows a toggled aim (`tests/toggle_input_probe`).
* **Stance Transition:** Smooth stance interpolation (`stance_lerp_speed = 12.0`) between standing height (`1.8m`) and crouching height (`1.0m`), with ceiling raycast clearance checks.

## Stamina and Exhaustion
<!-- lat: { "require-code-mention": true } -->
High-mobility actions drain a bounded stamina pool to prevent infinite sprinting and grapple evasion:
* **Stamina Pool:** Authorised base `100.0` stamina, scalable via meta upgrades in the Armory.
* **Drain Rates:** Sprinting drains `20.0/s`, tether winching drains `26.0/s`, melee shoves cost `18.0`, and dashes cost `12.0`.
* **Exhaustion Lockout:** Hitting `0` stamina triggers the `_stamina_exhausted` lockout. The player cannot sprint or grapple until stamina regenerates back past `stamina_recover_threshold` (`30.0`).
* **Recovery:** Begins after `0.5s` delay with a baseline regeneration rate of `18.0/s`.

## Tactical Maneuvers: Dash, Slide, and Grapple
<!-- lat: { "require-code-mention": true } -->
Advanced movement mechanics give players defensive evasion and repositioning tools:
* **Dash:** A rapid burst of speed (`20.0 m/s` for `0.16s`, `1.1s` cooldown) accompanied by a "Perfect Dodge" bonus window against incoming projectile fire.
* **Tackle:** every dash tick, `Player._tackle_tick` sweeps a `TACKLE_RADIUS` (0.9 m) sphere `TACKLE_REACH` (1.1 m) ahead of the chest on the enemy layer: each robot not yet in `_tackled` this dash takes `tackle_damage` (18, source the player) and, unless boss-class (`score_value` >= 1000) or a flyer (`hover_height`), is `launch`ed along the dash at `tackle_push` (9 m/s) with `tackle_lift` (4.5 m/s) up, so it counts as thrown ([[level-system#Hazards and Objectives]]: a bed melts it, a wall or a drop scraps it). Hijacked robots sit on the player layer and are never swept. The first tackle teaches `MECHANIC_HINTS.tackle`. `tests/dash_tackle_probe`.
* **Slide:** Crouching while sprinting converts forward momentum into a low friction slide (`12.5 m/s`, duration `0.7s`) that clears low obstacles.
* **Grappling Hook:** Shoots a physics tether toward world geometry (`Layer 1`), pulling the player toward the anchor point with stamina-dependent winching.
* **Launch:** `Player.launch(v, seconds)` (called by a jump pad, [[level-system#Jump Pads]]) sets the velocity and suspends air control for the flight, so the solved arc lands where it was aimed; on touchdown horizontal speed drops to a quarter so the player sticks the landing on the deck.

## Night Vision
<!-- lat: { "require-code-mention": true } -->
Night-vision goggles let the player see in the dark that shot-out lamps and blackouts make ([[level-system#Darkness and Shootable Lights]]).

* The goggles are a pickup (`Pickup.Kind.NIGHT_VISION`, `scenes/pickups/night_vision.tscn`, def pickup type `nightvision`) near the spawn on GPT and again on SUBLEVEL; it removes itself once owned. `GameState.grant_night_vision` sets `has_night_vision` for the run (saved as `night_vision`, cleared by `reset_run`, kept across a Daily Op) and teaches the key.
* `Player.toggle_night_vision` (action `night_vision`: N / D-pad down, rebindable via `GraphicsSettings.KEYBIND_ACTIONS`) shows a `NightVision` ColorRect, the last child of PostFX, running `shaders/night_vision.gdshader`: auto-gain 1 - exp(-l x gain), a blurred phosphor bloom, grain, scanlines and a round goggle mask, with a 0.35 s power-up flash. It emits no light, so unlike `flashlight_on` it never gives the player away. `tests/night_vision_probe`, `tests/night_vision_shot`.

## Neural Uplink
<!-- lat: { "require-code-mention": true } -->
Look at a robot you have hijacked ([[enemies#Collisions and Hijacking]]) and press interact to ride it: `NeuralUplink` (`scripts/systems/neural_uplink.gd`, built by the player as its `NeuralUplink` child) moves the mind into the chassis for 20 s.

* The body stays where it was left: `Player.linked_out` routes `_physics_process` into the frozen branch the death state uses and drops mouse look, and the weapon rack is disabled. The body is still a target; 20 damage to it snaps the link.
* The uplink owns a chase camera (4.2 m back, pulled in by a world ray) and writes `EnemyBase.pilot_move`, `pilot_yaw` and `pilot_lift`; `EnemyBase._hijack_process` hands a ridden unit to `_pilot_process` instead of the hijack brain and the burnout clock.
* Fire calls `EnemyBase.pilot_fire`: 34 damage per second at the chassis's own cadence (`pilot_cooldown`, from `attack_cooldown`), a hitscan from the muzzle for gunners and a 4.5 m frontal slam at x1.6 for brawlers (`attack_range` <= 4.5). Shots snap to a hostile within 6 deg of the crosshair. Flyers (`pilot_flies`) climb on jump and dive on crouch.
* Fire goes through `EnemyBase.pilot_signature(aim)`, which defaults to `pilot_fire` and is overridden where the chassis's own attack is the point (#343): the seeker dives up to 14 m at the aim and detonates (the chassis is spent, the ride ends), the GUNNER spins up (cadence 0.32 to 0.08 s over 10 held rounds, same DPS), the RAPTOR's belly gun strafes 3 half-shots per pull (1.5x the generic DPS), and the BRUTE pounds the ground all round it (6 m) instead of the frontal slam. The HOWITZER (640 HP) is over `HIJACK_BOSS_HP` and cannot be ridden at all.
* Every ending (interact again, the clock, body damage, the chassis dying or being freed, a chassis whose own loop never reaches the hijack path) calls `release_pilot`, which burns the chassis out credited to the player. `riding` tracks a ride apart from `robot`, because a freed chassis compares equal to null. Escort allies refuse the link. `tests/neural_uplink_probe`.

## Adversarial Patch
<!-- lat: { "require-code-mention": true } -->
Press the patch key (`adversarial_patch`: T / D-pad left, rebindable) and robot vision misreads the player as a household object for 15 s, 2 charges per level.

`AdversarialPatch` (`scripts/systems/adversarial_patch.gd`) is the player's `AdversarialPatch` child.

* `EnemyBase._compute_can_see` hands a confirmed sighting of a patched player to `AdversarialPatch.classify`, which raises the robot's `patch_confidence` by eyes-on time over 1.2 s (at 3 m) to 8 s (at 25 m); it sees the player only at 1.0. Out of sight it decays 0.15/s. Robots already hunting start at 0.6; bosses (score 1000+) see through.
* A tag over each robot that has looked shows its read: a decoy class and a falling percentage, then HUMAN in red.
* A shot (`GameState.shot_registered`) breaks the patch. A vision scanner ignores a patched player beyond 4 m ([[level-system#Vision Scanners]]).
* Melee while patched calls `tag_robot`: the robot is mislabeled for 8 s ([[enemies#Collisions and Hijacking]]) and the patch is spent. `tests/adversarial_patch_probe`.
## Network Breach
<!-- lat: { "require-code-mention": true } -->
Hold the breach key (`breach`: B / D-pad right, rebindable) to slow time and mark every networked thing in view; release to take over the one under the crosshair.

The scan runs at `SCAN_SCALE` (0.3) for up to `SCAN_MAX` (3 real s) and marks what is in range (35 m), in view (40 deg) and in line of sight; the pick is the nearest within 12 deg of the crosshair.

`NetworkBreach` (`scripts/systems/network_breach.gd`) is the player's `NetworkBreach` child; it pays from `bandwidth` (100, `REGEN` 7/s, paused while scanning).

* Targets are the `breachable` group (each with `breach_ready`, `breach_cost`, `breach_label`, `breach`) plus live robots: `SentryTurret` turns ALLIED (50), an exploding `Destructible` detonates (30), `LaserGate` goes dark for `BREACH_TIME` 6 s (35), a route `FirewallBarrier` opens for good (80; a lockdown door, `quiet`, is never offered); a robot is EMP-jammed for `JAM_TIME` 3 s (25).
* Bosses (the hijack line, `HIJACK_BOSS_HP`) are never offered. `tests/network_breach_probe`, `tests/network_breach_shot` (windowed).

## Photo Mode
<!-- lat: { "require-code-mention": true } -->
From the pause menu (or P while paused): the game stays frozen and a free camera starts at the eye, with the HUD, every overlay and the gun hidden.

`PhotoMode` (`scripts/ui/photo_mode.gd`) is built by the HUD (`hud.gd` `open_photo_mode`) and runs while the tree is paused.

* WASD flies (sprint x3, jump/crouch up/down), the mouse looks, the wheel zooms between `FOV_MIN` 20 and `FOV_MAX` 100; the camera stays within `RADIUS` (12 m) of where it started.
* TAB cycles `FILTERS` (none, noir, sepia, punch, vignette) on `shaders/photo_filter.gdshader`; ENTER saves a PNG to `user://screenshots/` (`capture`, the help line hidden for the frame); ESC restores the camera and every hidden node's visibility and lands on the pause menu. `tests/photo_mode_probe`, `tests/photo_mode_shot` (windowed).

## Co-op
<!-- lat: { "require-code-mention": true } -->
Local split-screen co-op is being built in stages: the player registry (1), per-player input (2) and the split screen (3), the down and revive rules (4) and the menu entry (5) are in (#402).

* **Registry:** `GameState.players()` (every player, by `player_index`), `living_players()`, `primary_player()` (player one) and `nearest_player(pos)` (the nearest one still standing). `Player.player_index` is 0 or 1; `Player.is_down()` marks a player robots and hazards look past.
* **Rules for callers:** a robot's target and a hazard's range check ask for the nearest player (`EnemyBase._find_player`); damage zones, area attacks and screen shake loop over every player (`GameState.shake_players`), with a hazard's shared cooldown started after every player in it has been tested; things that follow one view (the anchor and jammer aim tools, the AI Director's profile, telemetry, the behaviour clone) use player one.
* **Input:** each player reads its own `PlayerInput` (`scripts/player/player_input.gd`, `Player.input`). `PlayerInput.setup_coop(p1_pad, p2_pad)` turns co-op input on: player two reads `p2_` copies of every action, made on first use from its pad bindings with the device set to player two's pad, and player one's pad bindings narrow to player one's pad on every lookup. Keyboard and mouse (and the cheat words) stay with player one. Right-stick look is the `look_*` actions (`register_look_actions`), so each copy answers only its own pad. The weapon rack, Neural Uplink, NETWORK BREACH and the adversarial patch read their player's input; world consoles (the reward rewriter, the jammer and anchor tools) still read player one's. `reset_coop` drops every `p2_` action. `tests/coop_input_probe`.
* **Down and revive:** a player at 0 HP while a partner still stands goes DOWN (`Player.downed`, `is_down()`) instead of ending the level, and `GameState.on_player_downed` toasts it. The partner holds interact within `Player.REVIVE_RANGE` (2.5 m) for `REVIVE_TIME` (3 s; letting go starts over) and they stand back up at `REVIVE_HEALTH_FRAC` (50%) where they fell. The last one standing going down is game over. `GameState.respawn_at_checkpoint` brings every player back, partners 1.6 m to player one's right. Score is GameState's, so it is already shared. `tests/coop_revive_probe`.
* **Split screen:** with co-op input on, a built level (and level 01) adds player two beside player one (`GameState.spawn_coop_partner`) and `SplitScreen.attach` splits the screen. The players stay in the level; each half is a SubViewport on the level's World3D whose camera copies its player's view (the uplink camera while riding) after every other `_process`, and the root viewport stops drawing 3D. Each player's CanvasLayers draw in its half via `custom_viewport`, set with the layer out of the tree (set in place, freeing the level errored once per layer), and the layer's controls hang off a `SplitFrame` sized to the half (a control straight under a CanvasLayer lays out against the window even with `custom_viewport` set). Viewmodels sit on render layer 11 + index, drawn only by their own camera; each player wears a `CoopAvatar` capsule on layer 13 + index, drawn only by the other. Player one's HUD moves into the left half; player two gets a `CoopHud` (health, stamina, ammo, crosshair, revive state). `tests/coop_split_probe`.
* **Menu:** the main menu's Co-op button opens `CoopJoin` ("press A on the second controller"); the first pad button pressed calls `PlayerInput.setup_coop(other_pad_or_-1, that_pad)`. The button then names player two's pad, and pressing it again calls `reset_coop`. Play or Continue starts the game, and every level spawns player two while co-op input is on. `tests/coop_menu_probe`.
* **Guard:** `tests/coop_registry_probe` fails on any `get_first_node_in_group("player")` outside `game_state.gd` and `hud.gd` (the HUD binds to its own player in a later stage).

## Camera Feel and Combat Feedback
<!-- lat: { "require-code-mention": true } -->
Visual and kinetic camera dynamics provide visceral combat immersion:
* **Head Bob & Strafe Tilt:** Dynamic head bobbing (`bob_amplitude = 0.04`) and lateral roll when strafing (`1.4 deg`) create momentum.
* **Impact Trauma & Directional Kick:** Taking damage applies camera punches away from the hit vector (`hit_kick_amount`) and roll (`hit_kick_roll_deg`), with trauma-decaying screen shake.
* **Blast Screen-Warp:** Explosions and heavy impacts push up to 3 concurrent shockwave rings (`_screen_shocks`) into the post-processing shader for chromatic dispersion and distortion.
* **Lens Flare:** `Player._build_lens_flare` puts a `LensFlare` under `PostFX` before the post overlay. `LensFlare.source_for` picks the light: the brightest `DirectionalLight3D` on a procedural/physical sky, the `moon_dir` on a night_sky level (weaker), the def's measured `hdri_sun_dir` on an HDRI sky (none without one; `tools/hdri_sun_dir.gd` finds the photo's sun), none in interiors. Occlusion is a fan of `RAYS` physics rays plus `ray_hits_box` against the boxes of visual-only scenery in group `flare_occluder` (`Skyline.flare_boxes`); the lens dirt is a texture baked once by `dirt_texture`. Off with the advanced post-process setting. `tests/lens_flare_probe`.
