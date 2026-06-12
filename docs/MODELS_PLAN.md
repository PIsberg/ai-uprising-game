# Real-Model Upgrade Plan

Replacing the remaining procedural primitives with real (CC0) models, ordered
by how much screen time each thing gets. Pattern proven by the robot, weapon,
and pickup swaps: keep every collision shape, script, and group untouched —
swap only the visual children — and verify with a screenshot probe + headless
level loads before committing.

## What is still procedural

- All 8 props in `scenes/props/`: car, fence, crate, barrel, server_rack,
  terminal, gas_canister, lamp_post (BoxMesh/CylinderMesh builds).
- Suburb houses: builder boxes + prism roofs + door/window trim
  (`level_builder.gd::_build_buildings`).
- Ammo box pickup (deliberately kept — current look approved).
- Gun-range targets, portal, grenade projectile, intro-cutscene chore props.

## Sources (all CC0, no licensing risk)

- **Sci-Fi Essentials Kit** (Quaternius) — already partially in the repo;
  the full archives enumerate: Prop_Crate (+Large/Tarp variants), Barrel1,
  Barrel2 (open/closed), Locker, Chest, Desk_S/M/L, Shelves ×4, Chair,
  SatelliteDish, Mine, Grenade, Mug, Prop_Ammo (+Small/Closed), and textured
  guns (Pistol/Revolver/Rifle/Sniper). Texture batches 1+2 already imported.
- **Kenney kits** (kenney.nl) — City Kit Suburban (complete houses with
  varied roofs), City Kit Roads, Car Kit (sedans, wrecks), Furniture Kit.
  Same source as the Blaster Kit already in use; GLB, -Z facing.
- **Quaternius Ultimate Modular Sci-Fi** — wall/corridor/greeble pieces if
  interior levels ever need dressing beyond textured boxes.

## Phase 1 — kit props already on disk (low effort, every level benefits)

Crates and barrels appear as cover in nearly every arena.

1. `crate.tscn` → Prop_Crate (mix in Crate_Tarp/Large via a variant export).
2. `barrel.tscn` → Prop_Barrel2_Closed; `gas_canister.tscn` →
   Prop_Barrel1 with the existing emissive hazard ring + explosion logic kept.
3. New prop types for level defs: "locker", "shelves", "desk", "dish" —
   one PROP_SCENES entry each; lets the def files dress interiors richer.
4. Optional: ammo pickup → Prop_Ammo (only if the current box ever palls).

## Phase 2 — suburb curb appeal (highest visual impact)

1. Kenney City Kit Suburban: real house models replace the box+roof+trim
   build. Keep `_build_buildings` data-driven: map house `size`/`color` to
   the nearest kit model + tint, keep the box collision + navmesh obstacle
   exactly as-is (visual swap only).
2. Kenney Car Kit: `car.tscn` gets a real sedan/wreck; keep collision.
3. `fence.tscn`, `lamp_post.tscn` from the same kits for a coherent street.

## Phase 3 — interiors and details

1. `server_rack.tscn`, `terminal.tscn` → kit/modular models (server halls
   are GPT/Gemini's identity).
2. Weapon pickups: show the actual Kenney blaster GLB (via the existing
   REAL_MODELS map) instead of the primitive gun on the pedestal.
3. Gun-range targets, portal frame, intro chore props (mug/desk/chair from
   the kit make the "domestic calm" read instantly).

## Conventions and gotchas (learned the hard way)

- Quaternius glTF: +Z facing, real-metre scale; Kenney GLB: -Z facing.
- Keep texture batches shared — don't duplicate T_Props_* per model.
- After adding files run `--headless --import` TWICE on a clean checkout
  (first pass may resolve scene refs before the gltf imports).
- Verify visually with the probes: pickup_lineup, suburb_screenshot,
  flyer_screenshot, menu_screenshot — add one per new prop family.
- CREDITS.md entry per new pack (Kenney CC0 = courtesy credit).
