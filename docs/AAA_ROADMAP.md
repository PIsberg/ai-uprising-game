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

## Remaining toward full AAA (larger / asset- or art-dependent)
- **Skinned imported character meshes** (Mixamo/Synty) into the rig structure — true character fidelity; needs offline asset work.
- **Progressive robot damage states** (scorch, sparks, exposed core, limb loss); **AnimationTree** upper/lower-body split + look-at/IK so robots aim while walking.
- **Curated sampled SFX** (drop CC0 foley into `assets/audio/samples/`); adaptive music layers; reverb buses.
- **HDRI sky**, per-surface impact FX, shell casings, time-dilation on boss kills, controller rumble.
- **Production polish** — main-menu cinematic, settings menu exposing quality tiers, key rebinding, save/checkpoints, perf-budget pass, full balance tuning.

> These remaining items are what separate a strong vertical slice from a shipped AAA title: volume of curated art/audio content and long-tail polish, not engine capability.
