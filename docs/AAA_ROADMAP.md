# AI Uprising — Road to AAA

Honest framing: "AAA" is a production *tier* (studio years, dedicated art/animation/audio/QA), not a switch.
What follows is the achievable path from this prototype toward that **look and feel**, ordered by impact-per-effort.
Items marked ✅ are DONE and **verified in-engine** (Godot 4.6.3 installed; each checked via headless load-tests + rendered screenshots — see `memory/project_aaa_pass.md`).

## ✅ Completed + verified (2026-06-07)
- ✅ **Cinematic post-process** — `shaders/post_process.gdshader` (vignette, chromatic aberration, film grain, unsharp), `PostFX` CanvasLayer below the HUD. Shader compiles on GPU.
- ✅ **Auto-exposure** — `CameraAttributesPractical` on the player camera (tuned so it doesn't pump).
- ✅ **Lighting** — soft penumbra sun (PSSM 4-split), volumetric fog (interior-only), SSAO/SSIL/SSR, glow, filmic grade. **Fixed a real bug**: SDFGI was smearing flat walls → disabled for open-sky; fixed mirror-walls (`wall_panel` metallic 0.45→0).
- ✅ **Render quality** — 4096 shadows, high SSAO/SSIL/SSR quality, MSAA, anisotropic (`project.godot`).
- ✅ **Game feel** — trauma-squared rotational camera shake, strafe lean, counter-phase bob, sprint FOV, per-shot recoil trauma.
- ✅ **Robots rigged** — android, mech, colossus = articulated joint rigs + AnimationPlayer (idle/walk/attack/stagger), verified striding. Terminator = imported mesh (whole-body anim, correct for it); spider = procedural legs. All 5 appropriately animated.
- ✅ **Real PBR textures** — CC0 ambientCG (Concrete034/036, MetalPlates006) on floor/walls/metal, triplanar; brushed-metal anisotropy on core metals.
- ✅ **Decals + impact FX** — bullet scorch `Decal` (oriented to hit normal) + flash light + outward sparks; grenade ground-scorch that lingers/fades.
- ✅ **Hit markers + damage numbers** — crosshair pop (red on kill) + floating world-space `Label3D` damage numbers + audio tick.
- ✅ **Sky + reflection probes** — richer procedural sky (sun disc), box-projected `ReflectionProbe` per level (interior/exterior) for grounded off-screen reflections.
- ✅ **Audio** — sampled-audio OVERRIDE layer (drop real files in `assets/audio/samples/<id>.*`, synth fallback) + per-environment ambient beds (drone/wind).
- ✅ **QA pass** — all 8 campaign levels load CLEAN (fixed navmesh warnings); difficulty scaling verified (EASY/NORMAL/HARD); benign exit-leak diagnosed.
- ✅ **New level** — "Mistral Cryo-Core" (cyan indoor) added to the campaign (now 8 levels), verified.

## ✅ Graphics overhaul pass (2026-06-09, `graphics-overhaul` branch)
- ✅ **BeveledBoxMesh** — scripted PrimitiveMesh with chamfered edges; all robot plates and builder geometry get edge highlights (kills the "extruded blockout" look). Headless regression: `tests/bevel_smoke.tscn`.
- ✅ **Robot silhouettes** — android/mech/colossus slimmed + beveled, panel-line glow strips, antenna, mech side vents + visible gun barrel; brute/sniper code-built chassis beveled.
- ✅ **Environment detailing** — skirting/cornice trim, vertical wall ribs, panel seams, ceiling pipe runs, light-fixture housings under every point light (density follows graphics tier).
- ✅ **HDRI sky** — CC0 Poly Haven "Industrial Sunset" wired via `env.hdri` (suburb level); PanoramaSkyMaterial + sky IBL.
- ✅ **Texture variety** — Concrete031 (weathered outdoor walls) + MetalPlates007 (alternating cover plates); detail-normal overlay on floor/wall to break 1K tiling.

## ✅ Blast screen-warp + signal glitch (2026-07-26)
- ✅ **World-anchored shockwave refraction** — explosions bend the IMAGE, not just the camera. `post_process.gdshader` carries `uniform vec4 shockwaves[3]` (screen-UV centre, progress, strength); `Player._handle_screen_shock` re-projects each live blast's world position into UV every frame, so a ring stays pinned to its detonation as you turn. Up to 3 at once; a 4th blast evicts the weakest LIVE ring, never the newest.
- ✅ **Broad reach off one primitive** — `ExplosionFX._kick_player` (every grenade/explosion), the OVERLOAD ultimate, the hijack-grenade spike, and `EnemyBase.spawn_shockwave_ring` (mech stomp, manus finger-drum, smasher wake-slam, titan/colossus entrances) all push a distance-scaled warp.
- ✅ **Signal-corruption pass** — `uniform float glitch` drives banded horizontal tearing plus a hard RGB split; fires on the OVERLOAD EMP backwash and on a nearby hijack spike, decaying on its own clock.
- ✅ **Tier-gated + accessible** — the whole pass rides the existing Advanced Post-Process toggle, so LOW/MEDIUM tiers and motion-sensitive players opt out through a control that already exists.
- ✅ **Verified** — `tests/screen_shock_probe` (suite) covers ring lifecycle/eviction/projection/glitch decay. `tests/screen_shock_shot` + `tests/screen_shock_verify` unit-test the shader against a static checker (grain/warp/glitch zeroed so it is time-invariant) and assert the ring lands at the expected crest: peak 9536× median, bin 11 vs expected 10.

> **Godot 4.8 check (dev-2, 2026-07-26):** of the 46 merged PRs in the 4.8 milestone labelled `topic:rendering`, every one is a bug fix. The only additive graphics items in the whole 4.8 line so far are ASTC 6x6 compression profiles (GH-115003), a shader `bool`→`float` implicit conversion (GH-120715) and skipping shadow rendering for inactive particles (GH-118449). Nothing there justifies moving a shipped build onto a pre-release snapshot — staying on 4.7.1.

## ✅ Fluids integrated with the floor (2026-07-27)
Water and lava beds read as slabs laid ON the ground rather than liquid filling it. Measured cause: a hard-cut plane ~6 cm above an unbroken floor, wrapped in a rim box standing 12 cm proud with vertical sides.
- ✅ **`shaders/water.gdshader`** (new) — replaces a plain alpha `StandardMaterial3D`. Shoreline that dissolves toward the rim, screen-texture refraction through the ripple normal, depth-graded colour (shallow margins → dark centre), scrolling ripple normals, surf where geometry breaks the surface.
- ✅ **`shaders/fluid_margin.gdshader`** (new) — flush shoreline band replacing the raised rim box. Solid across the footprint, fading out over ~1.4 m, so floor → shore → fluid carries no silhouette. For water it doubles as the bed.
- ✅ **`lava.gdshader`** — cooling crust toward the rim, chewed up by the flow field but sealed at the outermost sliver, so the transition runs molten → crust → scorched rock → clean floor.
- ✅ **Measured, not asserted** — peak adjacent-pixel step at the rim: **water 0.2530 → 0.0169 (93% softer)**, **lava 0.1301 → 0.0401 (69%)**, via a git-stash A/B on an isolated rig (`tests/fluid_shot` + `tests/fluid_edge_verify`).

> Three measurement traps worth remembering, all of which produced confidently wrong answers first:
> 1. A 10–90% transition **width** is meaningless for lava — its flow veins swing wider than the shore does, so it measures turbulence. Peak gradient at a *known* rim position is robust.
> 2. The amber hazard frame sits exactly on the rim and is deliberately hard-edged; it swamped the metric until `fluid_shot` hid it (by material signature, so the stashed old build is treated identically).
> 3. Fixing the water surface **exposed a new hard edge** — the opaque bed plane underneath, whose own silhouette was revealed once the surface above it correctly faded to clear. Measured 2.6× *worse*. Bed and shore had to become one fading plane.

## ✅ Playtest loop pass (2026-09-11 → 09-12, PRs #76–#96, open for review)
Headless "play it and find things" loop: run the sweep instruments, chase every outlier with a
per-robot telemetry rig, fix with a red-then-green probe, PR. Each item below names its probe.
- ✅ **Real bugs** — Continue lost Armory supplies (`save_probe`); HOWITZER shells fell 7 m short
  (loft solved for g=9.8 vs project gravity 24, `howitzer_hit_probe`); WARBOT cross-fire never hit
  (fixed 6° V ≈ three capsule radii at 11 m, `warbot_crossfire_probe`); an enemy inside the player's
  capsule stopped attacking (LOS ray started inside the shape, `pointblank_los_probe`); the soft
  enemy-separation push was a per-frame impulse, flinging players off walkways
  (`separation_push_probe`); Armory purchases were silent (`sound_id_probe`).
- ✅ **Coverage gates** — every `tr()` literal in 5 locales (`i18n_coverage_probe`, 41 strings
  translated), every sound id (`sound_id_probe`), every typed level-def entry
  (`level_def_coverage_probe`), Continue from every level (`continue_sweep_probe`), every scene through
  the loading screen's threaded path (`threaded_load_probe`), damage math measured in-engine
  (`damage_math_probe`).
- ✅ **Load time** — first level 13.5 s → 1.7 s by resolving `LevelBuilder`'s scene tables lazily, plus
  a menu-time warm-up (`warm_cache_probe`).
- ✅ **Polish** — MANUS got real phases (`manus_phase_probe`), Flash Intensity now covers world light
  bursts (`flash_intensity_probe`), pause-menu FIELD MANUAL (`field_manual_probe`), Continue names the
  saved level, Damage Taken / Damage Number Size / Subtitle Size accessibility sliders.
- **Open** — every active robot costs ~1 ms of physics-tick time, engine-side (issue #89,
  `docs/PERF_NOTES.md`); MANUS phase-3 cadence and the narrower WARBOT lane need a playtest.

## ✅ Eye-level look audit, measured (2026-09-12)
Every campaign level shot from the spawn at eye height, then scored (`tests/look_capture` +
`tools/look_metrics.py`: mean luminance, black/blown share, saturation, hue entropy, Laplacian
sharpness). Three harness traps had to be fixed before the numbers meant anything: the camera
stared into the nearest wall on corner spawns (now a raycast yaw sweep picks the clearest
sightline), it sat inside the player's own body mesh, and the robots engaged the invulnerable
player during the settle so the blast screen-warp smeared half the frames into rings (the player
is now parked and frozen for the capture).
- ✅ **Flash-light regression caught on the way** — `GraphicsSettings.flash_energy` had been
  dropped by the #87 squash; every muzzle flash / impact / explosion light script-errored.
  Restored, and `flash_intensity_probe` finally joined both suite lists (PR #98).
- ✅ **Single-hue night levels** — titan, archon, uplink and overseer lit everything with the
  same blue: blue sun, blue ambient, saturated blue fog, and archon had not one warm light among
  ten. Mean saturation 0.89–0.98 (nearly every pixel fully saturated). Moon-white key, greyer
  haze, lower glow, 1–3 warm accent lamps each: saturation now 0.60–0.76, mean luminance up
  ~40%, the concrete walls show their texture again. Gemini got the lighter version.
- ✅ **Convoy had no `env` block at all** — the only level rendering the builder's generic grey
  default (saturation 0.19, the flattest frame). Now a moonlit night highway under sodium lamps.
- ✅ **Grok** — darkest frame in the campaign (mean luminance 0.08); ambient/sun lifted, two of
  the nine red lamps turned cool so the red has something to play against.
- **Hivemind, left as is** — 77% of the frame under 2% luminance, but it is the Tron-style
  mesh look (black planes, glowing grid seams): lifting ambient/sun and the floor albedo
  moved mean luminance 0.06 → 0.06, so the change was reverted rather than shipped blind.
- Judged fine and left alone: desert, frostbreak, water_world, suburb/suburb_boss, neon (its
  black is the arcade look), sublevel (dark corridor + light strip, tuned earlier), gpt's blown
  floor grid (owner-approved crisp look), guardrails' red floor + cyan HUD panel (intentional).

## Remaining toward full AAA (larger / asset- or art-dependent)
- **Skinned imported character meshes** (Mixamo/Synty) into the rig structure — true character fidelity; needs offline asset work.
- **Progressive robot damage states** (scorch, sparks, exposed core, limb loss); **AnimationTree** upper/lower-body split + look-at/IK so robots aim while walking.
- **Curated sampled SFX** (drop CC0 foley into `assets/audio/samples/`); adaptive music layers; reverb buses.
- ~~Per-surface impact FX, shell casings, time-dilation on boss kills, controller rumble.~~ **All four shipped** (audited 2026-07-26): `Impact.set_surface`/`_spawn_debris` (metal/dirt/wood/stone sparks, smoke and fragments), `Weapon._eject_brass` + the `brass_tink` synth, `GameState.boss_killcam`, `Haptics.pulse`.
- **Production polish** — main-menu cinematic, settings menu exposing quality tiers, key rebinding, save/checkpoints, perf-budget pass, full balance tuning.

> These remaining items are what separate a strong vertical slice from a shipped AAA title: volume of curated art/audio content and long-tail polish, not engine capability.
