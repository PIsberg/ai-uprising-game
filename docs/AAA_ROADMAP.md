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

## Remaining toward full AAA (larger / asset- or art-dependent)
- **Skinned imported character meshes** (Mixamo/Synty) into the rig structure — true character fidelity; needs offline asset work.
- **Progressive robot damage states** (scorch, sparks, exposed core, limb loss); **AnimationTree** upper/lower-body split + look-at/IK so robots aim while walking.
- **Curated sampled SFX** (drop CC0 foley into `assets/audio/samples/`); adaptive music layers; reverb buses.
- ~~Per-surface impact FX, shell casings, time-dilation on boss kills, controller rumble.~~ **All four shipped** (audited 2026-07-26): `Impact.set_surface`/`_spawn_debris` (metal/dirt/wood/stone sparks, smoke and fragments), `Weapon._eject_brass` + the `brass_tink` synth, `GameState.boss_killcam`, `Haptics.pulse`.
- **Production polish** — main-menu cinematic, settings menu exposing quality tiers, key rebinding, save/checkpoints, perf-budget pass, full balance tuning.

> These remaining items are what separate a strong vertical slice from a shipped AAA title: volume of curated art/audio content and long-tail polish, not engine capability.
