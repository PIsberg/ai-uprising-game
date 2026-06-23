# Editing the robot models with Blender (headless)

This project's enemy robots are downloaded CC0 GLBs (Quaternius mechs, the Godot
`RobotExpressive` humanoid, Kenney parts). We make them look **fierce** by adding
geometry — horns, tusks, spiked pauldrons, blades, back-crests — to the existing
meshes and re-exporting *forked* GLBs, so the originals (and any enemy still using
them) are untouched.

All of this is done with **Blender driven headlessly** (no GUI dragging): a Python
(`bpy`) script reads a small JSON config describing the parts to add, attaches them
to the right bone, and exports a new GLB plus a quick preview render. The render
loop is the fast iteration path; the real check is re-importing into Godot.

> Status: `reaper`, `hunter`, `gunner`, `raptor` ship fierce forks (see
> `assets/models/robots/quaternius_*_fierce.glb` / `*_bladed.glb`). The humanoid
> (`quaternius_heavy` = `RobotExpressive`, used by terminator/sentinel/mauler) is a
> known-hard case — see [Gotchas](#gotchas).

## Install

Blender is free / open-source. Installed once via winget:

```sh
winget install --id BlenderFoundation.Blender -e
```

Binary (Windows): `C:/Program Files/Blender Foundation/Blender 5.1/blender.exe`.
Run any script with:

```sh
"C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" \
  --background --python tools/blender/<script>.py -- <args...>
```

`--background` = no window. Everything after `--` is passed to the script.

## The pipeline

```
probe a model  ->  write a parts config  ->  fierce2.py builds + exports + renders
   (bones,           (JSON: spikes/blades        |
    extents,          per bone)                  v
    facing)                              quick Blender preview PNG
                                                  |
                                                  v
                                     copy GLB into assets/, godot --headless --import,
                                     load the scene, assert animations survived,
                                     then screenshot in-engine (tests/fierce_probe.tscn)
```

### 1. Probe the model first

Never place parts blind. `tools/blender/probe.py` dumps mesh names, per-bone vertex
extents, the bone list, and the animation clips; `tools/blender/bones.py` adds bone
world positions and a base render so you can confirm **facing and scale**.

```sh
blender --background --python tools/blender/probe.py -- assets/models/robots/quaternius_gunner.glb
blender --background --python tools/blender/bones.py -- assets/models/robots/quaternius_gunner.glb /tmp/base.png
```

Facts worth knowing up front:
- Quaternius `CharacterArmature` bots (`bot`, `gunner`, `flyergun`) face **−Y**
  (front), **+Z up**, confirmed by the red `Eye` bone sitting at −Y. They are a
  **single skinned mesh** with vertex groups — the easy case.
- Every Quaternius GLB ships a stray unparented `Icosphere` (junk). The script strips it.
- The Quaternius mechs import **untextured**; the in-game look comes from
  `RobotModel` (tint + menace emission). Added parts reuse a dark source material so
  the engine tint stays uniform — don't bake new colors into the GLB.

### 2. Write a parts config

A config is JSON: input GLB, output fork, preview path, rig mode, and a list of
parts. Each part is a `spike` (cone) or `blade` (box) placed at `loc` (the model's
own Blender space), rotated `rot` (degrees), sized, and bound to a `bone`.

See `tools/blender/cfg_gunner_bladed.json` for a complete example. Coordinates come
straight from the probe extents.

### 3. Build it

```sh
blender --background --python tools/blender/fierce2.py -- tools/blender/cfg_gunner_bladed.json
```

`fierce2.py`:
- imports the GLB, strips junk,
- builds each part, applies its transform,
- **attaches** it (see rig modes below),
- exports the forked GLB (`export_animations` + `export_skins` on),
- renders an auto-framed workbench preview for a fast eyeball.

Iterate on the config + re-run until the preview looks right.

### 4. Verify in Godot (the real test)

```sh
cp <fork>.glb assets/models/robots/
godot --headless --import                      # generates the .import + uid
godot --headless --script tools/blender/verify_glb_example.gd   # asserts AnimationPlayer + clips
godot res://tests/fierce_probe.tscn            # windowed: screenshots the fierce models in-engine
```

Wiring an enemy to its fork is a one-line edit in the enemy `.tscn`: change the
model `ext_resource` `path` **and** `uid` (read the uid from the new `.glb.import`).
Anim names (`CharacterArmature|Idle` …) and the mesh scale transform are preserved
by the fork, so it's a drop-in.

## Rig modes (`"rig"` in the config)

| mode | when | how parts attach |
|------|------|------------------|
| `skin` | single skinned mesh w/ vertex groups (Quaternius `bot`/`gunner`/`flyergun`) | new part gets a vertex group named after the bone (weight 1) and is **joined** into the main mesh; animates perfectly. **Reliable.** |
| `childmesh` | multi-mesh, bone-parented parts (`RobotExpressive`/`quaternius_heavy`) | skins each part to its bone. Works for size but see the gotcha. |

## Gotchas

- **Place against the *mesh*, not the rest bones.** On `RobotExpressive` the meshes
  are bone-parented in a *modeled* pose (head mesh sits at z≈3) while the rest-pose
  bones are elsewhere (head bone at z≈0.67). Use per-mesh world bounds
  (`tools/blender/meshbounds.py`), not bone positions.
- **The humanoid carries a 100× object scale.** Joining a scale-1 cone into that
  mesh, or object-parenting to it, mangles the part size. Skinning avoids the scale
  problem but then the part tracks the *bone* while the dome tracks via *bone-parent*
  — different binds — so the added crown **floats above the head** in Godot. The
  correct fix for this model is a Godot-side `BoneAttachment3D` on the Head bone with
  a measured dome offset (the project already does bone-driven attachment in
  `ModelPoser`). Deferred; the three Quaternius bots don't have this problem.
- **`Date.now()` / random** aren't needed; keep configs deterministic so a re-run
  reproduces the exact fork.

## Files

- `tools/blender/probe.py` — structure + per-bone extents + clips
- `tools/blender/bones.py` — bone world positions + base render
- `tools/blender/meshbounds.py` — per-mesh world bounds (for bone-parented models)
- `tools/blender/fierce2.py` — the config-driven build/export/render engine
- `tools/blender/cfg_*.json` — example part configs (one per enemy flavor)
- `tests/fierce_probe.tscn` / `.gd` — in-engine screenshot of the fierce models
