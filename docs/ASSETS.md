# Asset Sourcing Guide

The current build uses CSG/primitive placeholders that work, look passable under PBR lighting, and let you tune mechanics first. Replace them in order of visual impact: **weapons → enemies → environment**.

## Where to source realistic, free, license-clean assets

Always **double-check the individual asset's license** — site-wide "free" claims sometimes have exceptions.

### General PBR / models
| Source | License | Best for |
|---|---|---|
| [Sketchfab](https://sketchfab.com/3d-models?features=downloadable&licenses=322a749bcfa841b29dff1e8a1bb74b0b) | CC-BY / CC0 (filter!) | Weapons, props, enemies — huge selection |
| [Quaternius](https://quaternius.com/) | CC0 | Stylized to semi-realistic; great for rapid swap-in |
| [Kenney](https://kenney.nl/assets) | CC0 | Lower-poly, but reliable and free |
| [Poly Haven](https://polyhaven.com/) | CC0 | Best-in-class HDRIs + PBR textures + some models |
| [ambientCG](https://ambientcg.com/) | CC0 | PBR material library (concrete, metal, plastic) |
| [Free3D](https://free3d.com/) | mixed | Check per-asset license |
| [Itch.io 3D asset packs](https://itch.io/game-assets/free/tag-3d) | mixed | Some great curated FPS packs |

### Sci-fi FPS specific (search terms)
- "sci-fi rifle PBR" / "energy pistol low poly PBR"
- "combat drone quadcopter PBR"
- "humanoid robot PBR rigged" (rigged is harder to find free)
- "mech walker PBR"

### Audio (gunshots, robot SFX, ambient)
- [Freesound](https://freesound.org/) — CC0/CC-BY, filter carefully
- [Pixabay Sound Effects](https://pixabay.com/sound-effects/) — royalty free
- [Sonniss GDC bundles](https://sonniss.com/gameaudiogdc) — huge free pro-grade packs (CC-licensed)

### HDRIs for skyboxes / image-based lighting
- [Poly Haven HDRIs](https://polyhaven.com/hdris) — load via `Sky` → `PanoramaSkyMaterial` in the WorldEnvironment.

## Importing into Godot 4

### Models
1. Drop `.glb` / `.gltf` files into `assets/models/<category>/` — Godot auto-imports.
2. Open the imported file → **Advanced…** to:
   - Generate LODs (`Meshes` → `Generate Mipmaps/LODs`)
   - Strip animations you don't need
   - Set material import to "Use External" if you want to override
3. Drag the imported scene into the relevant placeholder scene (e.g. `scenes/weapons/rifle.tscn`) and delete the placeholder `MeshInstance3D`s.

### Textures (PBR)
For a single PBR material:
1. Right-click in FileSystem → New → `StandardMaterial3D`.
2. Set:
   - **Albedo → Texture**: `<name>_diff.png` (or `_basecolor`)
   - **Metallic → Texture**: `<name>_metal.png` (use `Texture Channel: Red`)
   - **Roughness → Texture**: `<name>_rough.png` (use `Texture Channel: Red`)
   - **Normal Map → Enabled + Texture**: `<name>_nor_gl.png` (use the OpenGL variant — Godot 4 expects it)
   - **AO → Enabled + Texture**: `<name>_ao.png` if present
3. Assign to the mesh's `Material Override`.

### HDRI sky
1. Open `assets/environments/default_env.tres`.
2. In the embedded `Sky` resource: set `Sky Material` → `PanoramaSkyMaterial`, assign your `.hdr`/`.exr`.
3. Set `Ambient Light → Source` to "Sky" so the world picks up the HDRI for IBL.

## What to swap, in order

1. **Player viewmodel weapons** (highest screen real-estate per second)
   - `scenes/weapons/rifle.tscn` → replace the BoxMesh `Body`/`Barrel`/`Grip` with a single imported model. Keep the `Muzzle` Node3D positioned at the barrel tip.
2. **Drone** — easiest enemy: a static mesh + four spinning rotors. Add an `AnimationPlayer` or just rotate rotor nodes in `_process`.
3. **Android** — needs a humanoid rig + idle/walk/shoot animations. Mixamo (`https://www.mixamo.com/`) has free rigged characters and animations; export as `.fbx` → import via Godot's FBX importer (Godot 4.3+) or convert to GLB first.
4. **Mech** — biggest screen real-estate enemy. Mixamo doesn't cover mechs well; Sketchfab is your best bet.
5. **Environment** — replace box geometry with a modular sci-fi kit (search "sci-fi corridor modular PBR"). Re-bake the NavigationMesh after.

## Performance budget for "realistic" look in Godot 4

- Keep player viewmodels under **~15k tris** (visible 100% of the time)
- Enemies: ~10–25k tris each
- Use the **Forward+** renderer (already set) for IBL + SDFGI/SSIL
- Enable **MSAA 2× or 4×** for clean edges (project.godot already sets MSAA 2×)
- Use **glow** sparingly — already enabled in `default_env.tres`
- Bake lightmaps with `LightmapGI` for the level once geometry is final

## Mixamo workflow (humanoid androids)

1. Upload a humanoid GLB to https://mixamo.com (or use one of their stock characters).
2. Apply animations: `Idle`, `Walking`, `Rifle Aim Walk`, `Firing Rifle`, `Death From Front`.
3. Download as FBX with skin, 30 FPS.
4. In Godot: open imported scene → set animations to loop, mark `Idle` and `Walking` as the default.
5. Replace the placeholder `Android` mesh in `scenes/enemies/android.tscn` with the imported scene; wire animations from `EnemyAndroid` via `$AnimationPlayer.play(...)` in `_on_enter_state`.
