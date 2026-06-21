# Level Editor — Plan & Spec

Status: proposal / not yet implemented. Target branch: `feat/level-editor`.

## 1. Summary

Add an in-game **Level Editor**: load any existing level, build new ones, place
enemies / bosses / obstacles / weapons / powerups, choose the level type
(interior vs open-sky + theme + weather), set the objective, then **playtest**
and **save**. Player-made levels are saved to `user://` and are loadable from a
"Custom Levels" menu.

## 2. The key insight — levels are already data

Every level in this game is a plain `Dictionary` returned by `LevelDefs` and
turned into a playable scene by `LevelBuilder` (`scripts/levels/level_builder.gd`).
Level 1 even uses this now (`level_01.tscn` runs `LevelBuilder` with `level_id="01"`).

That means **a level editor is a visual editor for one of these dicts**, with a
live preview produced by the same builder. We are not writing a new level
runtime — we are writing a UI that produces/edits the dict the runtime already
consumes. This keeps the scope tractable and guarantees the editor and the game
never diverge.

### The def schema (what the editor edits)

Top level: `name`, `objective`, `sign`, `slogans[]`, `tasks[]`, `open_sky`,
`floor_size` (Vector2), `floor_color`/`floor_material`, `spawn`/`exit` (Vector3),
`env{}`, and content arrays: `enemies[]`, `props[]`, `buildings[]`, `walls[]`,
`ramps[]`, `platforms[]`, `lights[]`, `holograms[]`, `fires[]`, `lava[]`,
`targets[]`, `lore[]`, plus singletons `hero{}`, `nexus{}`, `set_piece{}`,
`weapon{}`, `extra_weapons[]`. Theme/weather live under `env{}`
(`sky_*`, `fog*`, `sun_*`, `ambient*`, `glow`, `stars`, `hdri`, `weather`,
`lightning`, `building_tint`, …).

Content entry shapes the editor must read/write:
- enemy / boss: `{type, pos, count?, trigger?}` — `type` ∈ `LevelBuilder.ENEMY_SCENES`.
- prop / obstacle: `{type, pos, yaw?}` — `type` ∈ `LevelBuilder.PROP_SCENES`.
- weapon: `{scene, pos, color?}`.
- building: `{pos, size, color?, roof_color?}`; ramp `{pos,size,pitch?,yaw?}`;
  platform `{pos,size,color?}`; wall `{pos,size}`.
- light: `{pos, color, energy, range, flicker?}`.
- task: `{type, ...}` — `kill_all | key{pos} | destroy_core{pos,color,health} |
  collect_shards{points[]} | hack_terminal|sabotage{pos,seconds,color} |
  survive{seconds} | hold_zone{pos,seconds,radius,color}`.

## 3. Goals / Non-goals

**Goals (from the request)**
- Load existing levels for editing.
- Build new levels from scratch.
- Place enemies, obstacles, weapons, powerups, and bosses.
- Select level type (interior/open-sky + theme + weather).
- Set spawn, exit, and the objective/tasks.
- Playtest the in-progress level and save/load it.

**Non-goals (v1)**
- Free-form mesh/terrain sculpting (we place from the existing prop/building
  vocabulary, not arbitrary geometry).
- Scripting custom enemy behaviour or cutscenes.
- A networked / shared workshop (local `user://` files only; export/import via
  copy-paste text is supported).

## 4. Prerequisite engine changes (Phase 0)

These are small, self-contained changes the editor depends on:

1. **Raw def access** — `LevelDefs.get_def(id)` applies `WORLD_SCALE` (×1.4 on
   X/Z). Add `LevelDefs.raw_ids()` and keep `get_def` for the *final* coords.
   Decision: **the editor works in final world coordinates.** Loading an existing
   level uses `get_def(id)` (already final); saved custom defs carry
   `"world_scale": 1.0` and the builder skips re-scaling them (see #3).

2. **External / custom level loading** — add a `CustomLevels` autoload (or extend
   `LevelDefs`) with `load_def(path) -> Dictionary` and a registry. Extend
   `LevelBuilder._ready()` so that when `level_id` names a custom level (e.g.
   `level_id == "custom"` plus an exported `custom_path`, or `level_id` begins
   with `custom:`), it reads the def from the file instead of `LevelDefs`.
   Respect a def `"world_scale"` key (default `WORLD_SCALE` for built-ins, `1.0`
   for editor output).

3. **Serialization** — use Godot's `var_to_str` / `str_to_var`. They round-trip
   `Dictionary`/`Array`/`Vector2`/`Vector3`/`Color` losslessly, so the file
   format is literally the def. No hand-written JSON type-codec needed.
   File: `user://levels/<name>.lvl` (text). Provide copy/paste of the same text
   for sharing.

4. **Placeable powerups/weapons** — the builder currently *ignores* the
   `"pickups"` key (supplies drop from kills). Add `_build_pickups(def)`:
   for each `{kind, pos}` where `kind ∈ {health, ammo, overclock, overdrive}`,
   instance the matching scene (`scenes/pickups/health_pack|ammo_box|overclock|
   overdrive.tscn`). Weapons already place via `weapon`/`extra_weapons`.

5. **Builder re-entrancy for preview** — `LevelBuilder` builds once in `_ready`
   and bakes a navmesh. For the editor we do **not** run the full builder on
   every edit. Instead add a lightweight `EditorPreview` renderer (see #6) and
   only invoke the real `LevelBuilder` for **Playtest**. (Alternative if time is
   short: rebuild the whole `LevelBuilder` on a debounced timer — simpler but
   heavier; acceptable for v1.)

## 5. Architecture

```
MainMenu ──"Level Editor"──▶ LevelEditor (scene)
                                 │ holds: def: Dictionary  (the level being edited)
                                 ├─ EditorCamera        free-fly / orbit / top-down
                                 ├─ EditorPreview       renders floor+walls+entity markers from `def`
                                 ├─ Palette (UI)        categories → placeable items
                                 ├─ Inspector (UI)      edit selected entity / level settings
                                 ├─ Toolbar (UI)        New/Load/Save/Playtest/Undo/Redo/Grid
                                 └─ PlacementController  raycast-to-floor, place/select/move/delete
Playtest ──▶ writes def to user://_playtest.lvl ──▶ LevelBuilder(level_id="custom", path)
```

- **Single source of truth:** the in-memory `def` Dictionary. Every UI action
  mutates `def`; `EditorPreview` re-renders from `def` (diff or full rebuild of
  the cheap marker layer).
- **EditorPreview** mirrors the builder's vocabulary but cheap: floor plane sized
  to `floor_size`, perimeter walls, and a **marker** per entity (a representative
  mesh + a billboard label/icon: enemy = red capsule + type name, weapon = the
  pickup glow, prop = its real scene at low detail, light = a small bulb, spawn =
  green arrow, exit = portal ring, boss = larger red marker). Markers carry a
  back-reference to their `def` array + index for selection.
- Reuse existing data: `ENEMY_SCENES`, `PROP_SCENES`, pickup scenes,
  `EnemyCodex` (names/scale for nice labels), `LevelDefs` env presets.

## 6. Editor scene & components

**EditorCamera** — WASD + mouse-look free fly, plus a "top-down" toggle for
layout work; scroll to zoom. Mouse not captured (UI needs the cursor); hold RMB
to look.

**PlacementController**
- Raycast from cursor to the floor plane (y=0) → world position; optional grid
  snap (toggle, size 1 m default).
- Left-click with a palette item selected → append an entry to the right `def`
  array at that pos, spawn a marker.
- Left-click with no item selected → pick the marker under the cursor (select).
- Drag a selected marker → update its `pos` (write back to `def`).
- `Delete` removes the selected entry; `Ctrl+D` duplicates it at an offset.
- `R` / scroll-while-placing → rotate `yaw` (props/buildings).

**Palette** (categories, each lists items as buttons/icons):
- **Enemies** — every non-boss type in `ENEMY_SCENES` (drone, android, spider,
  mech, skitter, vacuum, hunter, reaper, strider, sniper, seeker, brute, gunner,
  raptor, mender, sentinel, mauler, alien). Placing sets `{type,pos}`; inspector
  exposes `count` (cluster) and `trigger` (radius, 0 = active at start).
- **Bosses** — `terminator, colossus, overseer, titan, archon` (the
  `BOSS_ENEMY_TYPES`). Same entry shape; the builder already handles their
  preview/boot logic.
- **Obstacles** — props from `PROP_SCENES` (car, crate, barrel, fence, lamp,
  server, terminal, monitors, canister, locker, shelves, desk, dish, tree,
  tree_small) **and** structural pieces (`walls`, `buildings`, `ramps`,
  `platforms`) with size handles in the inspector.
- **Weapons** — every scene in `GameState.ALL_WEAPONS` (+ sniper/magnum); writes
  `extra_weapons[]` (or the single `weapon` for the level's starter pickup).
- **Powerups** — health, ammo, overclock, overdrive → `pickups[]` (needs the
  Phase-0 `_build_pickups`).
- **Lights & FX** — point lights, `fires`, `holograms`, `lava`, `hero`/`nexus`
  landmarks.
- **Markers** — set `spawn` and `exit` (singletons; clicking re-places them).

**Inspector** — two modes:
- *Entity selected:* fields for that entry (type dropdown, count, trigger,
  color, size, yaw, etc.), plus Delete/Duplicate.
- *Nothing selected → Level Settings:* `name`, `objective`,
  **type** = Interior / Open-sky, **theme** = a dropdown of `env` presets
  (cloned from existing levels: GPT/Gemini/Claude/Grok/Suburb/Nexus/…),
  `floor_size`, `floor_color`, **weather** (none/rain/dust), `lightning`,
  `hdri` (none + the two installed skies), `music`, and the **tasks** list
  (add/remove/configure `kill_all`, `destroy_core`, `collect_shards`, …).

**Toolbar** — New, Load (lists built-in `LevelDefs` ids + `user://levels/*`),
Save / Save As, **Playtest**, Undo/Redo, Grid toggle/size, Validate.

## 7. Save / Load / Playtest

- **Save:** `var_to_str(def)` → `user://levels/<name>.lvl`. Stamp
  `def.world_scale = 1.0` and a `format_version`.
- **Load:** `str_to_var(FileAccess.get_as_text(path))`; rebuild markers.
  Loading a built-in: `LevelDefs.get_def(id)` (final coords) → treat as a new
  custom copy (don't overwrite the GDScript source).
- **Playtest:** write the current `def` to `user://_playtest.lvl`, change scene to
  a `level_custom.tscn` whose `LevelBuilder` has `level_id="custom"` and reads
  that path; a pause-menu "Return to Editor" restores the editor with the def
  intact. Playtest does the full real build (navmesh, FX, AI).
- **Shipping a custom level as campaign content (dev):** an "Export to GDScript"
  button prints a `static func _<id>() -> Dictionary` body to paste into
  `level_defs.gd` (authored coords = final ÷ scale), for promoting a player level
  into the real campaign.

## 8. Validation (Validate button + pre-Playtest)

Warn (non-blocking) on: no `spawn`, no `exit`, no `kill_all`/objective when
enemies exist, enemy/exit/spawn outside `floor_size`, `destroy_core`/`hold_zone`
referenced by a task but not placed, boss with no arena room, empty level.

## 9. Phased delivery

- **Phase 0 — Foundations** (no UI): raw/custom def loading in `LevelDefs` +
  `LevelBuilder`, `var_to_str` save/load helper, `_build_pickups`, a
  `level_custom.tscn`. Verifiable headless by writing a `.lvl` and loading it.
- **Phase 1 — Skeleton editor:** editor scene + camera + load a built-in def +
  `EditorPreview` markers + Save/Load + Playtest round-trip. Main-menu entry.
- **Phase 2 — Placement:** palette + click-to-place + select/move/delete/
  duplicate + grid snap for enemies, props, weapons, powerups, bosses,
  spawn/exit.
- **Phase 3 — Level settings & structures:** settings/theme/weather/tasks panel;
  size-handle editing for walls/buildings/ramps/platforms; lights/fires/holograms.
- **Phase 4 — Polish:** undo/redo stack, validation, multi-select, copy-as-
  template, export-to-GDScript, custom-levels browser in the main menu.

## 10. Risks & mitigations

- **Coordinate scaling confusion** (`WORLD_SCALE`). → Editor works in final
  coords; custom defs carry `world_scale=1.0`; builder honours it. Documented.
- **Live preview cost** (navmesh bake/particles per edit). → Cheap marker
  preview; full build only on Playtest.
- **Serialization drift** if the def schema grows. → `var_to_str` stores whatever
  keys exist; unknown keys are preserved on load; add `format_version`.
- **Picking/gizmos in 3D** can be fiddly. → Start with floor-plane raycast +
  click-select + drag-on-floor (no full 3-axis gizmo in v1).
- **Boss/special set-pieces** (archon waves, titan) assume specific arenas. →
  Allow placement but surface a validation hint; they already self-manage via
  `preview`/boot logic.

## 11. Testing / verification

- Headless: build a `.lvl` programmatically, load via `level_custom.tscn`,
  assert no script errors and that enemy/pickup counts match the def (extend the
  existing probe pattern in `tests/`).
- Windowed probes (per project norm): screenshot the editor with a loaded level,
  and a Playtest of a hand-placed level. (Note the import-stall gotcha: run
  `--headless --import` to completion before windowed probes.)

## 12. Rough effort

Phase 0 ≈ 0.5 day · Phase 1 ≈ 1 day · Phase 2 ≈ 1–1.5 days · Phase 3 ≈ 1–1.5
days · Phase 4 ≈ 1 day. MVP that satisfies the request (load/build/place
enemies+bosses+obstacles+weapons+powerups, pick level type, playtest, save) =
Phases 0–3.
