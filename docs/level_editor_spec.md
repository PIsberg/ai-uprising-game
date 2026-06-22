# Level Editor — Plan & Spec (v2, decisions locked)

Status: **IMPLEMENTED** (Phases 0–4) on branch `feat/level-editor`. Run it from
source with `godot --path . res://scenes/editor/level_editor.tscn`, or boot the
game with `--editor`. Headless self-test: `res://scenes/editor/level_editor.tscn
-- --editor-selftest` (PHASE1–4 PASS). See the implementation notes at the bottom.

This revision reflects the design interview. **Decisions are locked** (Section 3);
the rest of the doc is the build plan that follows from them.

## 1. Summary

A **developer-facing** level editor for authoring this game's levels visually:
load any existing level, build new ones, place enemies / bosses / obstacles /
weapons / powerups, set the level type + theme + weather, set spawn/exit and the
objective, manage the campaign order, then **playtest** in the real game.

It ships as a **second build of this same Godot project** (so it reuses every
enemy/prop scene, `LevelBuilder`, and asset, and can never drift from the game),
booting into the editor instead of the game.

## 2. The key insight — levels are already data

Every level is a plain `Dictionary` from `LevelDefs`, turned into a playable
scene by `LevelBuilder` (`scripts/levels/level_builder.gd`); level 1 already runs
this way. **The editor is a visual editor for that dict**, previewed with the
real builder. We are not writing a new level runtime.

### Def schema (what the editor edits)

Top level: `name`, `objective`, `sign`, `slogans[]`, `tasks[]`, `open_sky`,
`floor_size` (Vector2), `floor_color`/`floor_material`, `spawn`/`exit` (Vector3),
`env{}`, content arrays `enemies[]`, `props[]`, `buildings[]`, `walls[]`,
`ramps[]`, `platforms[]`, `lights[]`, `holograms[]`, `fires[]`, `lava[]`,
`targets[]`, `lore[]`, `pickups[]` (new), singletons `hero{}`, `nexus{}`,
`set_piece{}`, `weapon{}`, `extra_weapons[]`, plus `world_scale` (new, see 5.1).
`env{}` holds the full theme: `sky_*`, `fog*`, `sun_*`, `ambient*`, `glow`,
`brightness/contrast/saturation`, `stars`/`star_*`/`milkyway*`/`moon_*`, `hdri`,
`sky_energy`, `physical_sky`, `weather`, `lightning`, `building_tint`.

Entry shapes the editor reads/writes:
- enemy/boss `{type,pos,count?,trigger?}` (`type` ∈ `LevelBuilder.ENEMY_SCENES`;
  bosses = `LevelDefs.BOSS_ENEMY_TYPES`).
- prop/obstacle `{type,pos,yaw?}` (`type` ∈ `LevelBuilder.PROP_SCENES`).
- weapon `{scene,pos,color?}`; powerup `{kind,pos}` (`kind` ∈
  health|ammo|overclock|overdrive).
- building `{pos,size,color?,roof_color?}`; wall `{pos,size}`;
  ramp `{pos,size,pitch?,yaw?}`; platform `{pos,size,color?}`.
- light `{pos,color,energy,range,flicker?}`.
- task `{type,...}` — all of `kill_all | key{pos} | destroy_core{pos,color,health}
  | collect_shards{points[]} | hack_terminal|sabotage{pos,seconds,color} |
  survive{seconds} | hold_zone{pos,seconds,radius,color}`.

## 3. Locked decisions (from the interview)

| Area | Decision |
|---|---|
| Audience | **Dev tool** (yours). |
| App form | **Same project, second build** — boots into the editor; own export preset. |
| Save format | **Data files + GDScript export.** Edit/save `.lvl` (via `var_to_str`); a button generates the `level_defs.gd` `_<id>()` body for promoting to the campaign. |
| File location | **In-repo `res://dev_levels/`** (version-controlled). |
| Editing view | **Hybrid**: top-down layout view ↔ free-fly first-person, toggle. |
| Transforms | **Full gizmos — both** click-drag handles **and** Blender-style `G/R/S` + axis keys. |
| Geometry | Move/rotate/**scale** props; **resize** walls/buildings/ramps/platforms + floor size. |
| Preview | **Markers** while editing; **Playtest launches the game exe** with the level file. |
| Theme | **Full manual** env control (every knob). |
| Objectives | **All task types.** |
| New level | Dialog: **blank stub or copy an existing level**. |
| Campaign | Editor **also manages the campaign** (reorder/insert/remove). |
| Conveniences | **Undo/redo, grid snap (1 m / 15°, adjustable), multi-select + copy/paste, validation.** |

## 4. Architecture

```
[ Export preset A: "AI Uprising" ]      main scene = main_menu  (the game)
[ Export preset B: "AI Uprising Editor"] main scene = LevelEditor (the editor)

LevelEditor (scene)  — same project, reuses everything
  def: Dictionary                  # the level being edited (single source of truth)
  History (command stack)          # undo/redo wraps every mutation
  EditorCamera   top-down ⇄ free-fly toggle
  EditorPreview  cheap markers built from `def`
  Gizmo          runtime translate/rotate/scale (handles + G/R/S, axis + snap)
  Palette (UI)   categories → placeables
  Inspector(UI)  selected entity fields  /  level settings (full env)  /  campaign
  Toolbar(UI)    New·Load·Save·Export·Playtest·Undo·Redo·Grid·View·Validate

Playtest ──▶ run the GAME build exe:  AIUprising.exe --level res://dev_levels/<x>.lvl
                                       (in-editor dev: launch the game scene via OS.execute
                                        or change_scene to level_custom.tscn)
```

- **Single source of truth:** the in-memory `def`. Every action is a **Command**
  (do/undo) that mutates `def` and refreshes the affected marker(s). This gives
  undo/redo, copy/paste, and validation for free across all edit types.
- **EditorPreview** mirrors the builder vocabulary cheaply: floor sized to
  `floor_size`, perimeter walls, and one **marker** per entity (representative
  mesh/icon + label; enemy = red capsule + type, boss = larger, weapon = pickup
  glow, prop = its real scene low-detail, light = bulb, spawn = green arrow,
  exit = portal ring). Markers hold a back-ref to their `def` array + index for
  selection. Full lights/FX/AI happen only in Playtest.
- Reuses `ENEMY_SCENES`, `PROP_SCENES`, pickup scenes, `EnemyCodex`
  (names/icons), and the env presets in `LevelDefs`.

## 5. Prerequisite engine changes (Phase 0)

1. **`world_scale` reconciliation.** `LevelDefs.get_def()` multiplies footprint
   X/Z by `WORLD_SCALE` (1.4). The editor works in **final world coords**:
   loading a built-in uses `get_def()` (already final); saved `.lvl` files carry
   `world_scale = 1.0` and `LevelBuilder` skips re-scaling them.
2. **Custom-def loading.** Add `CustomLevels.load_def(path)` (uses `str_to_var`)
   and extend `LevelBuilder._ready()`: when `level_id == "custom"` (with an
   exported `custom_path`) it reads the def from the file instead of `LevelDefs`,
   honoring `world_scale`.
3. **`--level <path>` CLI boot.** A boot handler (in the game's entry, e.g. a
   small autoload or `main` scene) parses `OS.get_cmdline_args()`; if `--level`
   is present, load that file via `level_custom.tscn`. This is what Playtest
   shells out to.
4. **Serialization** via `var_to_str` / `str_to_var` — lossless for
   `Dictionary/Array/Vector2/Vector3/Color`. File: `res://dev_levels/<name>.lvl`
   (text), plus a `format_version`. (Caveat: `res://` is writable only when
   running from source — the dev workflow; an exported editor exe falls back to a
   path beside the executable.)
5. **`_build_pickups(def)`** — the builder currently ignores `"pickups"`; add
   placement of `{kind,pos}` from `scenes/pickups/health_pack|ammo_box|overclock|
   overdrive.tscn`.
6. **Data-driven campaign.** `GameState.CAMPAIGN` is a hardcoded `const`. Add
   loading of `res://dev_levels/campaign.json` (an ordered list of level
   ids/paths) when present, falling back to the const. The campaign manager
   writes this file; the GDScript-export button can also emit the `CAMPAIGN`
   array.
7. **Export presets.** Add a second preset whose main scene is the editor (or a
   `--editor` boot flag), so the editor ships as its own exe.

All of Phase 0 is verifiable headless (write a `.lvl`, boot the game with
`--level`, assert it builds with no errors).

## 6. Editor components

**EditorCamera** — top-down ortho/high-angle for layout; press a key to drop into
free-fly (WASD + RMB look) to inspect as you'll play. Scroll to zoom; frame-selected.

**Selection & Gizmos** — pick a marker by click (box-drag for multi-select).
Selected objects show a **transform gizmo**:
- Drag handles: 3 move arrows + 3 plane quads, 3 rotation rings, 3 scale boxes.
- Keyboard: `G`/`R`/`S` then optional `X`/`Y`/`Z` to constrain, click/enter to
  confirm, `Esc` to cancel.
- Snapping: position → grid (default 1 m), rotation → 15°, scale → 0.1; all
  adjustable in the toolbar and held-key to toggle.
- Per-type affordances: enemies/weapons/powerups = move+rotate (no scale);
  props = move+rotate(+uniform scale); structures (walls/buildings/ramps/
  platforms) = move+rotate+non-uniform scale; spawn/exit = move only.

**Palette** (categories):
- Enemies — non-boss `ENEMY_SCENES`; inspector exposes `count` + `trigger`.
- Bosses — `BOSS_ENEMY_TYPES` (terminator/colossus/overseer/titan/archon).
- Obstacles — `PROP_SCENES` props + structural walls/buildings/ramps/platforms.
- Weapons — `GameState.ALL_WEAPONS` (+ sniper/magnum) → `weapon`/`extra_weapons`.
- Powerups — health/ammo/overclock/overdrive → `pickups[]`.
- Lights & FX — point lights, `fires`, `holograms`, `lava`, `hero`, `nexus`.
- Markers — `spawn`, `exit` (singletons).

**Inspector** — three modes:
- *Entity:* fields for the selected entry (type, count, trigger, color, size,
  yaw…), plus Delete/Duplicate.
- *Level Settings:* `name`, `objective`, interior/open-sky, **full env** (every
  sky/fog/sun/ambient/grade/glow knob + weather + hdri + lightning +
  building_tint), `floor_size`/`floor_color`/`floor_material`, and the **tasks**
  list (add/configure all task types).
- *Campaign:* the ordered level list — drag to reorder, insert/remove, mark
  boss; saved to `campaign.json`.

**Toolbar** — New (blank | from template), Load (built-in ids + `dev_levels/*`),
Save / Save As, **Export to GDScript**, **Playtest**, Undo/Redo, Grid + snap
sizes, View toggle (top-down/fly), Validate.

## 7. Save / Load / Export / Playtest

- **Save:** `var_to_str(def)` → `res://dev_levels/<name>.lvl`; stamp
  `world_scale=1.0` + `format_version`.
- **Load:** `str_to_var` a `.lvl`, or `LevelDefs.get_def(id)` for a built-in
  (treated as a new editable copy — never rewrites the GDScript source).
- **Export to GDScript:** generate a `static func _<id>() -> Dictionary` body
  (authored coords) to paste into `level_defs.gd`, plus the updated `CAMPAIGN`
  list, for promoting dev levels into the shipped game.
- **Playtest:** run the **game build** with `--level res://dev_levels/<x>.lvl`
  (via `OS.execute`/`OS.create_process`); in an editor-from-source session it can
  instead `change_scene_to` `level_custom.tscn`. A pause-menu "Quit to Editor"
  (or just closing the playtest process) returns you to the editor.

## 8. Undo/redo, validation, multi-select

- **Undo/redo:** every mutation is a `Command {do(), undo()}` pushed on a stack;
  toolbar + `Ctrl+Z`/`Ctrl+Y`. Place/move/rotate/scale/delete/duplicate/paste and
  settings changes all go through it.
- **Multi-select + copy/paste:** box-select; group move/rotate/duplicate/delete;
  `Ctrl+C`/`Ctrl+V` within and across levels (clipboard holds entry dicts).
- **Validation (Validate + pre-Playtest):** warn on missing `spawn`/`exit`, no
  `kill_all`/objective while enemies exist, entities outside `floor_size`, a task
  that needs a placed target (`destroy_core`/`hold_zone`/`collect_shards`) but
  has none, empty level, boss with no room.

## 9. Phased delivery

- **Phase 0 — Foundations** (no UI): `world_scale` handling, `CustomLevels` +
  custom-def loading in `LevelBuilder`, `--level` CLI boot, `var_to_str`
  save/load, `_build_pickups`, data-driven campaign, `level_custom.tscn`, the
  editor export preset. Headless-verifiable.
- **Phase 1 — Editor shell:** editor boot scene, hybrid camera, load a def,
  marker preview, Save/Load to `dev_levels/`, New dialog (blank|template).
- **Phase 2 — Placement & gizmos:** palette, click-to-place all categories,
  selection, the transform gizmo system (handles + G/R/S + snap), delete/
  duplicate, multi-select + copy/paste, structure resize + floor size, undo/redo.
- **Phase 3 — Settings, objectives, env, campaign:** full env panel, all task
  types, spawn/exit, level meta, campaign manager, Export to GDScript.
- **Phase 4 — Polish & ship:** validation pass, Playtest via game exe + return,
  finalize the editor export preset, keybind/help overlay.

## 10. Risks & mitigations

- **Runtime gizmos** are the biggest new system (Godot's editor gizmos aren't
  available at runtime). → Build a focused gizmo: raycast handle-picking + drag
  on the active plane/axis, plus the `G/R/S` keyboard path; reuse one math core
  for both. Phase it (move first, then rotate/scale).
- **`res://` read-only when exported.** → Editor-from-source is the primary dev
  workflow (res:// writable); exported editor falls back to a path beside the exe.
- **Coordinate scaling.** → Editor in final coords; `world_scale=1.0` on saved
  defs; builder honors it. Documented.
- **Live preview cost.** → Cheap markers; full build only in Playtest.
- **GDScript export formatting / merge churn.** → Export is copy-paste assist,
  not an auto-writer; the live source of truth for dev levels is the `.lvl` files.
- **Boss/special set-pieces** assume specific arenas. → Allow placement; surface a
  validation hint; they self-manage via `preview`/boot logic.

## 11. Testing / verification

- Headless: programmatically write a `.lvl`, boot `--level` it, assert no script
  errors and that enemy/prop/pickup counts match the def (extend the `tests/`
  probe pattern).
- Windowed probes per project norm for the editor UI and a Playtest of a
  hand-placed level. (Gotcha: kill stray Godot processes and run
  `--headless --import` to completion before windowed probes — see
  `game-feel-and-builder-features` memory.)

## 12. Rough effort

Bigger than v1 due to gizmos + separate build + campaign tooling + all tasks:
Phase 0 ≈ 1 day · Phase 1 ≈ 1 day · Phase 2 ≈ 2–3 days (gizmos) · Phase 3 ≈ 1.5–2
days · Phase 4 ≈ 1 day. **≈ 6.5–8 days.** A usable internal MVP
(load/build/place everything, gizmo move+rotate, manual env, playtest, save +
export) lands at the end of Phase 3.
