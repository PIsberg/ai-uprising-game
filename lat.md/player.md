# Player Systems and Locomotion

This document specifies the player character mechanics, movement physics, stamina constraints, tactical abilities, and camera feel in **ai-uprising-game**.

## Locomotion and Stances
<!-- lat: { "require-code-mention": true } -->
The player controller (`scripts/player/player.gd`) implements a responsive First-Person CharacterBody3D:
* **Movement Speeds:** Authorised walk (`5.5 m/s`), sprint (`9.0 m/s`), and crouch (`2.8 m/s`) velocities with snappy acceleration (`18.0`) and friction (`14.0`).
* **Jump Mechanics:** Includes standard jump (`7.5 m/s`), coyote time (`0.1s`), jump buffering (`0.12s`), and a sprint-jump momentum boost (`1.3x`) charged by continuous running.
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
* Every ending (interact again, the clock, body damage, the chassis dying, a chassis whose own loop never reaches the hijack path) calls `release_pilot`, which burns the chassis out credited to the player. Escort allies refuse the link. `tests/neural_uplink_probe`.

## Camera Feel and Combat Feedback
<!-- lat: { "require-code-mention": true } -->
Visual and kinetic camera dynamics provide visceral combat immersion:
* **Head Bob & Strafe Tilt:** Dynamic head bobbing (`bob_amplitude = 0.04`) and lateral roll when strafing (`1.4 deg`) create momentum.
* **Impact Trauma & Directional Kick:** Taking damage applies camera punches away from the hit vector (`hit_kick_amount`) and roll (`hit_kick_roll_deg`), with trauma-decaying screen shake.
* **Blast Screen-Warp:** Explosions and heavy impacts push up to 3 concurrent shockwave rings (`_screen_shocks`) into the post-processing shader for chromatic dispersion and distortion.
* **Lens Flare:** `Player._build_lens_flare` puts a `LensFlare` under `PostFX` before the post overlay. `LensFlare.source_for` picks the light: the brightest `DirectionalLight3D` on a procedural/physical sky, the `moon_dir` on a night_sky level (weaker), the def's measured `hdri_sun_dir` on an HDRI sky (none without one; `tools/hdri_sun_dir.gd` finds the photo's sun), none in interiors. Occlusion is a fan of `RAYS` physics rays plus `ray_hits_box` against the boxes of visual-only scenery in group `flare_occluder` (`Skyline.flare_boxes`); the lens dirt is a texture baked once by `dirt_texture`. Off with the advanced post-process setting. `tests/lens_flare_probe`.
