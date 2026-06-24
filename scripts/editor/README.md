# AI Uprising — Level Editor

A built-in, developer-facing editor for the game's levels. Levels are plain data
(the same `Dictionary` `LevelBuilder` consumes), so the editor is a visual editor
for that data with a live marker preview and an in-game playtest. Built levels are
saved as `res://dev_levels/*.lvl` and can be exported to GDScript for the campaign.

---

## Starting the editor

Pick whichever fits:

- **From source (normal dev):**
  ```
  godot --path . res://scenes/editor/level_editor.tscn
  ```
- **From the game build, via flag:**
  ```
  AIUprising.exe --editor
  ```
- **Dedicated editor build:** export the **"Windows Editor"** preset
  (`build/windows/ai-uprising-editor.exe`). It carries the `editor_build` feature
  and boots straight into the editor — no flag needed. (Make a desktop shortcut.)

Headless self-test (sanity check, no window):
```
godot --headless res://scenes/editor/level_editor.tscn -- --editor-selftest
```
Expect `PHASE1 … PHASE5 PASS`.

---

## Screen layout

```
┌─────────────────────────── toolbar ───────────────────────────┐
│ New │name│ Save │ load▼ │ Load │ View(Tab) │ Snap │ Validate │ ▶Playtest │ status │
├──────────┬────────────────────────────────────┬───────────────┤
│ PALETTE  │                                    │  INSPECTOR     │
│ (place)  │            3D viewport             │  (edit fields) │
│          │      floor · grid · markers        │                │
│          │                                    │                │
├──────────┴────────────────────────────────────┴───────────────┤
│                      help / selection status                   │
└────────────────────────────────────────────────────────────────┘
```

- **Palette (left):** categories of things to place.
- **Viewport (centre):** the level as cheap **markers** (labelled icons), not the
  full build. Use **Playtest** to see the real thing.
- **Inspector (right):** edits the selected object, or — with nothing selected —
  the **level settings** (name, env, tasks, tools).

---

## Camera

`Tab` toggles **Top-down** ⇄ **Free-fly**.

| | Top-down (layout) | Free-fly (inspect) |
|---|---|---|
| Move | `W A S D` pan | `W A S D` + `Q`/`E` down/up |
| Look | `RMB`-drag = rotate | `RMB`-drag = look |
| Zoom | mouse wheel | move forward/back |

---

## Building a level

### Place objects
1. Click an item in the **Palette** (it arms placement; the status shows what's armed).
   A translucent **ghost** of the item now follows the cursor so you can see what
   and where you're about to drop — and the toolbar **readout** (right of the
   status, cyan) shows the live snapped coords, e.g. `▶ building  @ 8.0, 6.0 m`.
2. **Left-click** on the ground to drop it (snapped to the grid).
3. Click **▣ SELECT / MOVE** (top of the palette) to stop placing (clears the ghost).

Categories: **Enemies**, **Bosses**, **Obstacles** (props), **Structures**
(wall / building / ramp / platform), **Weapons**, **Powerups**
(health/ammo/overclock/overdrive), **Lights / FX** (point light, fire, hologram,
hero monolith, nexus tower). **Spawn** and **Exit** already exist on every level —
select and move them (they can't be deleted).

### Select & transform
- **Left-click** a marker to select it; **Shift+click** to add/remove from the selection.
- **Drag a selected marker** to move it on the ground plane.
- **Gizmo handles** appear on the selection:
  - **arrows** → move along X / **Y** / Z (Y lets you set height in the viewport),
  - **cubes** → scale a structure along an axis,
  - **ring** → rotate (yaw).
  Drag a handle to use it.
- **Keyboard transform** (Blender-style): `G` move, `R` rotate, `F` scale, then
  optional `X`/`Y`/`Z` to lock an axis; **click** confirms, **Esc**/`RMB` cancels.
- **Snap** toggles in the toolbar (grid **1 m**, angle **15°**).

During a `G`/`R`/`F` transform the toolbar **readout** shows the running figure —
`MOVE  Δ 4.0, 2.0 m · X`, `ROTATE  45°`, `SCALE  ×1.40` — so you can drag to an
exact measurement. With one object selected it shows that object's position (and
size, for structures).

### Edit exact values
Select one object → the **Inspector** shows its fields (type, count, trigger
radius, position incl. **Y**, size, yaw, colour, energy, range, text, scale,
height…). Editing writes straight into the level.

---

## Level settings (nothing selected)

With nothing selected the Inspector shows the whole level:

- **Meta:** name, objective, sign, open-sky toggle, floor size, floor colour.
- **Environment (full manual):** sky/horizon/ground/fog/ambient/sun colours, fog
  density, ambient/sun energy, glow, brightness/contrast/saturation, **weather**
  (none/rain/dust), **lightning**, **stars**, **HDRI** sky.
- **Objectives / tasks:** add/remove and configure any of: `kill_all`, keycard,
  destroy core, collect shards, hack terminal, sabotage, survive timer, hold zone.
- **Tools:** Export to GDScript · Campaign manager.

---

## Save / load

- **Save:** type a name in the toolbar field, click **Save** →
  `res://dev_levels/<name>.lvl`.
- **Load:** the dropdown lists `built-in: <id>` (an **editable copy** of a shipped
  level — great as a starting template) and `file: <name>` (your saved levels);
  pick one and click **Load**.
- **New:** a blank level (floor + spawn + exit). To start "from a template", just
  **Load a built-in** and **Save** under a new name.

Files are stored with `world_scale = 1.0` so the editor's coordinates match the
game exactly (no surprise ×1.4 scaling on play).

---

## Playtest

Click **▶ Playtest** — the level is saved and launched in the real game
(`level_custom`). To come back:

- press **F2**, or
- open the pause menu (`Esc`) → **"Return to Editor"**.

**Validate** (toolbar) flags problems first (missing spawn/exit, enemies with no
objective, a task whose target isn't placed, out-of-bounds spawn/exit). It only
warns — Playtest still runs.

---

## Putting a level in the campaign

Two complementary tools (Inspector → Tools, and the Campaign manager):

1. **Campaign manager** — reorder / insert / remove levels and **Save
   campaign.json**. The game reads `res://dev_levels/campaign.json` and uses that
   order in place of the built-in campaign. Quickest way to play-test a custom
   level in sequence.
2. **Export to GDScript** — writes `dev_levels/<name>_export.gd.txt` containing a
   `static func _<id>() -> Dictionary` body. Paste it into
   `scripts/levels/level_defs.gd` and add `"<id>": _<id>()` to `_defs()` to make
   the level a permanent, shipped campaign level.

---

## Keyboard reference

| Key | Action |
|---|---|
| `Tab` | Top-down ⇄ free-fly camera |
| `W A S D` | Pan / fly |
| `Q` / `E` | Fly down / up |
| `RMB` drag | Rotate / look |
| Wheel | Zoom (top-down) |
| `LMB` | Place (armed) · select · drag-move · grab handle |
| `Shift`+`LMB` | Add/remove from selection |
| `G` / `R` / `F` | Grab-move / rotate / scale (then `X`/`Y`/`Z` to lock an axis) |
| click / `Esc` / `RMB` | Confirm / cancel a transform |
| `Delete` / `Backspace` | Delete selection |
| `Ctrl+D` | Duplicate |
| `Ctrl+C` / `Ctrl+V` | Copy / paste |
| `Ctrl+Z` / `Ctrl+Y` | Undo / redo |
| `F2` (in playtest) | Return to editor |

---

## Files & notes

- Levels: `res://dev_levels/<name>.lvl` (text, `var_to_str`).
- Campaign order: `res://dev_levels/campaign.json`.
- GDScript exports: `res://dev_levels/<name>_export.gd.txt`.
- `res://` is writable only when running **from source** (the dev workflow). An
  **exported** editor `.exe` has a read-only `res://`, so it falls back to
  `user://dev_levels/`.
- The preview is intentionally lightweight (markers, no lights/particles/AI) so
  editing stays fast — Playtest is the real thing.

See `docs/level_editor_spec.md` for the design/architecture.
