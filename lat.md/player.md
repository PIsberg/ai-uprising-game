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

## Camera Feel and Combat Feedback
<!-- lat: { "require-code-mention": true } -->
Visual and kinetic camera dynamics provide visceral combat immersion:
* **Head Bob & Strafe Tilt:** Dynamic head bobbing (`bob_amplitude = 0.04`) and lateral roll when strafing (`1.4 deg`) create momentum.
* **Impact Trauma & Directional Kick:** Taking damage applies camera punches away from the hit vector (`hit_kick_amount`) and roll (`hit_kick_roll_deg`), with trauma-decaying screen shake.
* **Blast Screen-Warp:** Explosions and heavy impacts push up to 3 concurrent shockwave rings (`_screen_shocks`) into the post-processing shader for chromatic dispersion and distortion.
* **Lens Flare:** `Player._build_lens_flare` puts a `LensFlare` under `PostFX` before the post overlay. `LensFlare.source_for` picks the light: the brightest `DirectionalLight3D` on a procedural/physical sky, the `moon_dir` on a night_sky level (weaker), none on HDRI skies and interiors. Occlusion is a fan of `RAYS` physics rays plus `ray_hits_box` against the boxes of visual-only scenery in group `flare_occluder` (`Skyline.flare_boxes`); the lens dirt is a texture baked once by `dirt_texture`. Off with the advanced post-process setting. `tests/lens_flare_probe`.
