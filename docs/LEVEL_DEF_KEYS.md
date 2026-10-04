# Level Definition Keys

Levels are **data, not scenes**. Each level is one `Dictionary` entry returned
by a `_xxx()` function in `scripts/levels/level_defs.gd` (e.g. `_gpt()`,
`_titan()`) and collected in `LevelDefs._defs()`. `LevelBuilder`
(`scripts/levels/level_builder.gd`) reads that dictionary in `_ready`/`_build_*`
and constructs the actual geometry, lighting, hazards, tasks, and enemy
spawners at load time. `level_01.tscn` is the one hand-authored exception;
`.lvl` custom-editor levels flow through the same dictionary shape via
`level_custom.tscn`.

## World scale — the rule that has bitten this codebase before

`LevelDefs.get_def()` multiplies every **positional** value by
`WORLD_SCALE` (1.4) via the `_scaled()` helper before handing the dict to the
builder, so authored coordinates stretch the arena while heights and
human-scale content (props, enemies, pickup meshes) keep their authored size.
`_scaled()` has an explicit allow-list of which keys get scaled and how
(ground-plane `pos`/`size` for most; position-only for ramps, whose `size.z`
encodes slope and must NOT stretch; height stays sacred everywhere).

**Any new positional key you add to a level def MUST be added to
`LevelDefs._scaled()`, or it silently spawns at unscaled (pre-×1.4)
coordinates.** This is not hypothetical: it once buried an authored ramp foot
inside a boundary wall, and separately, a whole category of pickups shipped
off-position for the same reason (see below).

A related silent-no-op trap: `_build_pickups` originally only read
`p["kind"]`, but every hand-authored campaign def wrote `p["type"]` — so
**~88 authored pickups never spawned**, with no error anywhere (unknown dict
keys are just ignored). It now reads `type` first, falling back to `kind`
(the level editor's spelling). The general lesson holds for every table
below: a typo'd or unconsumed key is a silent no-op, not a crash — when in
doubt, grep `level_builder.gd` for the literal string before trusting a def.

Columns below: **Scaled?** = yes/no per `_scaled()`; **Probe** = the
headless test that exercises this key, left blank where none exists (do not
assume one exists just because the feature does).

---

## Geometry / Layout

| Key | Type | Effect | Consumed in | Scaled? | Probe |
|---|---|---|---|---|---|
| `floor_size` | Vector2 | Arena footprint (x, z); drives the floor slab, perimeter walls/ceiling, and is the reference size nearly every other builder pass reads | `_build_geometry`, `_build_wall_details`, `_build_gi`, and ~20 more `_build_*` passes | Yes (Vector2×s) | — |
| `world_scale` | float | Per-level override of the global 1.4 world scale (e.g. `1.0` for the convoy/guardrails levels whose geometry is hand-authored in world units) | `LevelDefs.get_def` | n/a (is the scale) | — |
| `open_sky` | bool | Switches indoor↔outdoor treatment across nearly every pass: no ceiling/cornice, weaker ambient crush, sun as key light, distance fog instead of volumetric fog, skips VoxelGI/floor-seams/pipes/facility-detail, enables skyline/stars/trees/streets/sky-traffic | `_build_environment`, `_build_geometry`, `_build_gi`, `_build_floor_seams`, `_build_pipes`, `_build_facility_detail`, `_build_trees`, `_build_skyline`, `_build_stars`, `_build_sky_traffic`, `_build_outdoor_detail` | No | — |
| `floor_material` | String (resource path) | Overrides the floor material entirely (e.g. the showcase vault's polished plate) | `_build_geometry` | n/a | — |
| `floor_color` | Color | Tints the floor via `_color_material` instead of the shared concrete texture | `_build_geometry` | No | — |
| `ceiling_color` | Color | Tints the ceiling panel (mirrors `floor_color`) so a heavily-themed hall doesn't wash out under the default light panel | `_build_geometry` | No | — |
| `walls` | Array<{pos,size}> | Interior cover/pillar boxes, alternating two plate materials | `_build_geometry`; also stripped of lava-overlapping entries by `_strip_lava_overlaps` | Yes (pos + size) | — |
| `platforms` | Array<{pos,size,color?}> | Solid collider boxes parented under the navmesh region (elevated walkable decks, bridges) | `_build_platforms` | Yes (pos + size) | — |
| `ramps` | Array<{pos,size,pitch?,yaw?}> | Climbable ramp geometry, solved to a true top-face walking line (no lip) | `_build_ramps` → `_add_ramp` → `_build_ramp_wedge` | pos only — `size` (rise/run) is deliberately **not** scaled | `tests/ramp_probe` |
| `stairs` | Array<{from,to,width?}> | Point-to-point ramp between two authored endpoints; ≥5m endpoints also get sky-bridge edge lighting | `_build_stairs` → `_add_ramp_between`/`_dress_bridge_edges` | from/to pos (ground-plane; height sacred) | `tests/ramp_probe` |
| `towers` | Array<{pos,height?,radius?}> | Climbable spiral-ramp tower to a rooftop vantage; also raises the room's structural ceiling height to clear tall towers | `_build_towers` → `_build_tower` | pos only | `tests/ramp_probe` |
| `gates` | Array<{axis,at,gap?,gap_pos?,height?,thick?,roofed?,beacon?}> | Full-height partition wall spanning the arena with one walkable gap — forces a serpentine route instead of a straight line to the exit | `_build_gates` → `_gate_beacon` | `at`/`gap`/`gap_pos` (floats); `height`/`thick` stay authored | `tests/route_probe`, `tests/campaign_nav_sweep` |
| `buildings` | Array<{pos,size,open?}> | Decorative solid house/building box; `"open": true` builds an enterable two-storey shell (door, interior ramp, upper floor, roof) instead | `_build_buildings` → `_build_open_building`; stripped of lava overlaps by `_strip_lava_overlaps` | Yes (pos + size) | `tests/layout_check` |
| `building_tint` | Color | Multiplies house/building albedo toward grim concrete (ruined-city reskin) | `_build_buildings`, `_build_open_building` | n/a | — |
| `no_exit` | bool | Skips building the exit Portal (sandbox levels leave via pause menu) | `_build_exit` | n/a | — |
| `spawn` | Vector3 | Player start position; also aims the player's initial facing at `exit` | `_place_player`, also read by `_build_trees`/`_build_streetlamps` to keep clutter off the entry | Yes | — |
| `exit` | Vector3 | Portal / extraction beacon position | `_build_exit`, `_place_player` (facing), `_build_trees`/`_build_streetlamps` (clutter avoidance) | Yes | — |
| `set_piece` | {pos,height?,face?} | A distant `BossTelegraph` silhouette figure (the "something huge is out there" beat) | `_build_set_piece` | pos + face | — |
| `hero` | {pos,color?,height?} | Focal monolith centrepiece on a stepped dais — real collidable cover plus a glowing core seam | `_build_hero` | No (only top-level placed-content groups get scaled; `hero`/`nexus` are read raw) | — |
| `nexus` | {pos,color?,height?} | The Sector-45 landmark spire (tall dark tower, sensor head with watching red eyes, halo, red key light) | `_build_nexus` | No | — |

## Lighting / Environment

All of these except `lights`/`hero_lights`/`light_shafts`/`streetlamp_*` live
nested inside the top-level `env` dictionary.

| Key | Type | Effect | Consumed in | Scaled? | Probe |
|---|---|---|---|---|---|
| `env` | Dictionary | Parent bag for sky/fog/grade/sun settings below | `_build_environment`, `_theme_color`, `_build_atmosphere`, `_build_weather`, `_build_ash`, `_build_lightning` | No | — |
| `hdri` | String (resource path) | Photographic CC0 Poly Haven sky instead of a procedural gradient | `_build_environment` | n/a | — |
| `physical_sky` | bool | Physically-based Rayleigh/Mie atmosphere sky, for naturalistic outdoor levels | `_build_environment` | n/a | — |
| `stars` | bool | Stylized night sky: tinted gradient + procedural stars/Milky Way/moon shader; also densifies/brightens streetlamps | `_build_environment`, `_build_streetlamps` | n/a | `tests/level_shot` (visual only, windowed) |
| `sky_top`, `sky_horizon`, `ground` | Color | Sky gradient stops (procedural sky, or the night-sky shader's zenith/horizon/ground) | `_build_environment` | No | — |
| `sky_energy` | float | Sky brightness multiplier (all three sky material types) | `_build_environment` | No | — |
| `turbidity` | float | Physical-sky atmospheric haziness | `_build_environment` | No | — |
| `star_density`, `star_brightness`, `star_tint` | float/float/Color | Night-sky shader star field tuning | `_build_environment` | No | — |
| `milkyway`, `milkyway_tint` | float/Color | Night-sky shader Milky Way band strength/color | `_build_environment` | No | — |
| `moon_dir`, `moon_color`, `moon_size`, `moon_glow` | Vector3/Color/float/float | Night-sky shader moon placement/look | `_build_environment` | No | — |
| `ambient`, `ambient_energy` | Color/float | Ambient light color/energy (energy is further scaled by an indoor/outdoor crush factor) | `_build_environment`, `_theme_color` (fallback theme color) | No | — |
| `sky_contribution` | float | How much of the ambient comes from the sky vs. flat ambient color | `_build_environment` | No | — |
| `glow`, `glow_strength`, `glow_bloom`, `glow_threshold` | float | Bloom/glow tonemap tuning; `glow_threshold` must stay ≥1.1 or interiors haze over (see `docs/AAA_ROADMAP.md`) | `_build_environment` | No | — |
| `fog`, `fog_density`, `fog_aerial` | Color/float/float | Distance-fog color/density and aerial-perspective strength (interiors auto-darken/thin these) | `_build_environment`, `_build_atmosphere` (dust-mote tint), `_build_weather` (dust particle tint) | No | — |
| `volumetric_density` | float | Overrides interior volumetric-fog density directly (showcase levels thicken the haze for god-rays) | `_build_environment` | No | — |
| `brightness`, `contrast`, `saturation` | float | Post-process color-grade adjustment | `_build_environment` | No | — |
| `split_tone` | bool | Opt out of the default teal-shadow/warm-highlight LUT (default true) | `_build_environment` → `_split_tone_lut` | n/a | — |
| `sun_rot`, `sun_color`, `sun_energy` | Vector3/Color/float | Directional sun light transform/color/energy | `_build_environment` | No | — |
| `weather` | String (`"rain"`\|`"snow"`\|`"dust"`\|`"storm"`) | Falling weather particles; `"rain"` also triggers wet-floor clearcoat, rain ambience, and lightning | `_build_geometry` (wet floor), `_build_environment` (ambience bed), `_build_weather`, `_build_lightning` | n/a | — |
| `lightning` | bool | Forces periodic sky-flash + thunderclap even without rain weather | `_build_lightning` | n/a | `tests/lightning_probe` |
| `ash` | bool | Slow-drifting ember motes rising off a foundry/lava floor | `_build_ash` | n/a | — |
| `lights` | Array<{pos,color?,energy?,range?,flicker?}> | Placed point lights (or AreaLight3D on HIGH/ULTRA indoors); also gets a visible housing/fixture, and the level's `_theme_color()` defaults to the first entry's color | `_build_environment`, `_build_wall_details` (fixture), `_theme_color`, `_build_light_shafts` | Yes (pos); `trigger`/`range` also defensively scaled by `_scaled()` though only `range` is actually read | — |
| `hero_lights` | Array<{pos,size?,color?,energy?,rot?,shadow?}> | Dramatic rectangular AreaLight3D key/rim lights for boss arenas, HIGH/ULTRA only | `_build_hero_lights` | No | — |
| `light_shafts` | `true` or Array<int> | God-ray cone under every (or selected) placed light | `_build_light_shafts` | n/a | — |
| `streetlamp_spacing`, `streetlamp_energy` | float | Overrides default streetlamp spacing/brightness (night levels get denser/brighter by default) | `_build_streetlamps` | No | `tests/dark_spot_probe` |
| `music` | String | Per-level music track id, overriding the id→track default map | `_build_environment` | n/a | — |

## Dressing / Visual

| Key | Type | Effect | Consumed in | Scaled? | Probe |
|---|---|---|---|---|---|
| `streets` | bool | Textured asphalt floor + painted crossroads/crosswalks/parking lot/traffic signs + streetlamps | `_build_geometry`, `_build_streets`, `_build_parking_lot`, `_build_traffic_signs`, `_build_streetlamps`, `_build_trees` (avoids carriageways) | n/a | `tests/dark_spot_probe` |
| `trees` | int | Count of volumetric billboard trees scattered outdoors (open_sky only), avoiding spawn/exit/streets/buildings | `_build_trees` | n/a (count, not position) | `tests/tree_probe` |
| `accents` | Array<{pos,size,color}> | Small emissive decorative boxes | `_build_accents` | Yes (pos + size, via the shared `walls`/`accents`/`platforms` scale group) | — |
| `props` | Array<{type,pos,yaw?}> | Destructible/decorative prop instances from `PROP_SCENES`, added to the navmesh region | `_build_props`; stripped of lava overlaps by `_strip_lava_overlaps` | Yes (pos); `trigger`/`range` defensively scaled but unused here | — |
| `disco` | Array<{pos,height?,radius?,colors?,speed?,mast?}> | Spinning mirror-ball rig + coloured sweeping spotlights (purely decorative) | `_build_disco` | No | — |
| `holograms` | Array<{pos,color?,text?,size?,height?}> | Floating propaganda HoloBillboard signs; if omitted (and not `friendly`/`no_holograms`/`horde_spawns`), two default billboards are placed automatically | `_build_holograms` | Yes (pos) | — |
| `no_holograms` | bool | Suppresses the automatic default hologram pair (only matters when `holograms` is unset) | `_build_holograms` | n/a | — |
| `friendly` | bool | Resistance-held space: skips hostile surveillance beacon sweeps and the default hologram pair | `_build_beacons`, `_build_holograms` | n/a | — |
| `fires` | Array<{pos,scale?}> | Burning fire/smoke particle effect at a point | `_build_fires` | Yes (pos) | — |
| `sign` | String | Facility billboard headline text (falls back to `name`) | `_build_signage` | n/a | — |
| `slogans` | Array<String> | Propaganda graffiti lines scattered on the walls; also seeds the hologram text pool when holograms don't specify their own `text` | `_build_signage`, `_build_holograms` | n/a | — |
| `name` | String | Level display title; billboard fallback when `sign` is unset | `LevelDefs.level_title`, `_build_signage` | n/a | — |

## Hazards

| Key | Type | Effect | Consumed in | Scaled? | Probe |
|---|---|---|---|---|---|
| `lava` | Array<{pos,size,dmg?,color?,water?,yaw?}> | Molten (or, with `water: true`, deep-water) hazard bed: carves the navmesh so enemies detour, burns the player on contact, and strips any floor-level clutter placed inside it (`_strip_lava_overlaps`) | `_build_lava`, `_build_environment` (hazard ambience bed), `_strip_lava_overlaps`/`_pos_in_lava`, `LevelDefs.level_hazard` (campaign-map sector flag) | Yes (pos + size as Vector2×s) | `tests/lava_probe`, `tests/hazard_probe` |
| `firewalls` | Array<{pos,length?,height?,yaw?,color?,node?,opens_on?,label?}> | Security firewall across a route: an energy sheet between two emitter posts that blocks ONLY the player (its own collision layer 8, which only `player.tscn`'s body masks), so robots, rounds and grenades pass and the navmesh never sees it. Drops when its relay node at `node` is shot, or when every task id in `opens_on` (String or Array) completes; `label` is the "FIREWALL BREACHED" callout text. Collision stands 1.5 m above `height`, so a sky-bridge well above the sheet passes over it: keep firewalls out of gaps a bridge threads at sheet height | `_build_firewalls` → `FirewallBarrier`/`FirewallNode` | Yes (pos, node, length) | `tests/firewall_probe` (every opener, objective and the exit reachable without crossing a still-closed firewall), `tests/firewall_shot` (windowed) |
| `jammer` | `true` or {radius?,lifetime?,max?,cooldown?,color?} | Grants the player the SIGNAL JAMMER beacon ability for the level | `_build_jammer` | n/a | `tests/jamming_probe` |

## Enemies / Encounters

| Key | Type | Effect | Consumed in | Scaled? | Probe |
|---|---|---|---|---|---|
| `enemies` | Array<{type,pos,trigger?,count?,pack?}> | Placed enemy spawner(s). `count` scatters a cluster from one entry (swarms); `pack` groups entries sharing an id into one squad that wakes together; `trigger` gates the spawn behind a radius instead of spawning on level load | `_spawn_enemies`; also feeds `LevelDefs.level_is_boss`, `GameState.level_par_time` (par time += 7s per enemy `count`) | Yes (pos); `trigger`/`range` (float) | `tests/pack_probe`, `tests/threat_probe` (report-only) |
| `horde_spawns` | Array<Vector3> | Enables endless-siege `HordeDirector` wave spawning instead of (or alongside) placed enemies; also suppresses the default hologram pair | `_build_horde`, `_build_holograms` | Yes | `tests/horde_screenshot` (windowed) |
| `supply_center` | Vector3 | Center point the horde director drops supplies around | `_build_horde` | Yes | — |

## Tasks / Objectives

Every entry in the `tasks` array is a Dictionary; `type` selects the task
kind and dispatches to `_register_task_entry`/`_activate_task`. A level with
no `tasks` key defaults to a single `kill_all` task.

| Key | Type | Effect | Consumed in | Scaled? | Probe |
|---|---|---|---|---|---|
| `tasks` | Array<Dictionary> | The mission checklist (see per-type rows below) | `_build_tasks`, `_register_task_entry`, `_activate_task` | Yes (pos/points/reinforce[].pos/waves[].enemies\|supplies[].pos) | `tests/objective_probe`, `tests/level01_task_probe` |
| `type` | String | One of `kill_all`, `kill_quota`, `key`, `destroy_core`, `collect_shards`, `hack_terminal`, `sabotage`, `survive`, `hold_zone`, `assassinate`, `generative_zone`, `none` | `_task_id`, `_register_task_entry`, `_activate_task` | n/a | — |
| `id` | String | Explicit checklist id (else a per-type default, e.g. `"key"`/`"hold"`/`"hvt"`) — required when multiple tasks of the same type coexist (e.g. staged `hold_zone` chains) | `_task_id` | n/a | — |
| `after` | String or Array<String> | Marks the task as a later STAGE: registers immediately (sealed/dimmed on the HUD) but only spawns once every listed prerequisite task id is complete | `_prereqs_of`, `_on_tasks_progress` | n/a | `tests/mission_arc_probe` |
| `reinforce` | Array (enemy specs) | On this task's completion, pours in a staggered enemy wave via the same spawner as placed enemies (an "objective tripped the alarm" reaction) | `_build_tasks`, `_on_tasks_progress`, `_spawn_reinforcements` | Yes (pos, within the `_scaled` tasks pass) | `tests/mission_arc_probe` |
| `label` | String | HUD checklist text for this task | `_register_task_entry` | n/a | — |
| `pos` | Vector3 | World placement of the task's object (keycard, core, console, HVT, hold-zone center, generative-zone field center) | `_activate_task` (all placed task types), `_reachable_task_pos` | Yes | `tests/task_reach_probe` |
| `count` | int | `kill_quota` goal — number of kills required | `_register_task_entry` | n/a | — |
| `points` | Array<Vector3 \| {pos}> | `collect_shards` pickup locations (hand-authored = raw Vector3; editor-authored = `{"pos":...}` dicts) | `_register_task_entry` (goal = count), `_activate_task` | Yes | — |
| `seconds` | float | Duration for `hack_terminal`/`sabotage` (hold-to-hack time), `survive` (hold length), `hold_zone` (dwell time) | `_register_task_entry`, `_activate_task` | n/a | — |
| `color` | Color | Accent color override for `destroy_core`/`hack_terminal`/`hold_zone`/`generative_zone` objective props | `_activate_task` | n/a | — |
| `health` | float | `destroy_core` max health | `_activate_task` | n/a | — |
| `radius` | float | `hold_zone` capture radius | `_activate_task` | n/a | — |
| `waves` | Array<{at,enemies,supplies?,label?}> | Escalating enemy waves (and optional mid-hold supply vents) fired during a `survive` task, reusing the reinforcement spawner | `_activate_task` → `SurviveTimer`, `_on_survive_wave`, `_spawn_reinforcements`, `_vent_supplies` | Yes (waves[].enemies/supplies pos) | `tests/purge_probe` (timer + GPT arc), `tests/survive_waves_probe` (every hold, live navmesh) |
| `enemy` | String | `assassinate` — the HVT's enemy type (default `"brute"`) | `_spawn_hvt` | n/a | — |
| `elite` | String | `assassinate` — elite affix applied to the HVT (default `"warden"`) | `_spawn_hvt` | n/a | — |
| `bulk` | float | `assassinate` — extra HP multiplier on top of the elite affix (default 2.2) | `_spawn_hvt` | n/a | — |
| `field_size` | Vector2 | `generative_zone` — grid footprint of the unstable-terrain field | `_activate_task` → `GenerativeZone` | No (read raw off the task dict, not through the positional `_scaled` pass) | `tests/guardrails_probe` |
| `cell` | float | `generative_zone` — grid cell size | `_activate_task` | No | `tests/guardrails_probe` |
| `accent`, `hazard_color` | Color | `generative_zone` — safe-cell / hazard-cell colors | `_activate_task` | n/a | `tests/guardrails_probe` |
| `hazard_period` | float | `generative_zone` — seconds between hazard regeneration ticks | `_activate_task` | n/a | `tests/guardrails_probe` |
| `floor_dot` | float | `generative_zone` — floor grid dot density/spacing | `_activate_task` | n/a | `tests/guardrails_probe` |
| `overload` | {trigger_label,core} | Climactic red-alert set-piece (`OverloadDirector`): when the task whose `label` matches `trigger_label` completes, every static light bleeds red/strobes and the `core` point erupts with periodic blasts | `_build_overload` | No | — |
| `objective` | String | HUD objective text and the exit Portal's on-screen prompt | `_build_exit`, `_apply_objective_text` | n/a | — |
| `weapon` | {scene,pos,color?} | The level's starting weapon pickup | `_build_weapon_pickup` → `_spawn_weapon_pickup` | pos | `tests/weapon_order_probe` |
| `extra_weapons` | Array (same shape as `weapon`) | Additional weapon pickups to find in the level | `_build_weapon_pickup` | Yes (pos) | `tests/weapon_order_probe` |
| `pickups` | Array<{type\|kind,pos}> | Hand-placed supply/powerup pickups. Accepts **both** `type` (used by every hand-authored campaign def) and `kind` (used by the level editor) — see the intro note above | `_build_pickups` | Yes (pos) | `tests/pickup_probe` |
| `targets` | Array<{pos,hp?,move?,speed?,color?}> | Pop-up range-target dummies (static, sliding, or armored) | `_build_targets` | Yes (pos) | — |
| `lore` | Array<{pos,id?,title?,text?,color?}> | Walk-up `LoreTerminal` that voices a recovered log through the broadcast bus | `_build_lore` | Yes (pos) | — |

## Misc

| Key | Type | Effect | Consumed in | Scaled? | Probe |
|---|---|---|---|---|---|
| `sign`, `name`, `slogans`, `objective` | — | See Dressing/Visual and Tasks/Objectives tables above (cross-cutting text keys used by multiple passes) | multiple | n/a | — |

---

## Possibly dead / unauthored-but-supported keys

These are read by `level_builder.gd` but were **not** found authored in any
current `level_defs.gd` entry (confirmed by grep, not by exhaustive proof —
re-check before relying on this). They are not bugs: the builder supports
them defensively / for future/editor use, they just aren't exercised by the
shipped campaign today.

- `gates[].thick`, `gates[].beacon` — both have working defaults (`1.0`,
  `true`); no current gate entry overrides them.
- `disco[].mast` — auto-derived from `open_sky` when unset; no rig currently
  forces it explicitly.
- `no_holograms` — supported by `_build_holograms`, but no current level sets
  it (levels either omit `holograms` and take the default pair, or set
  `friendly`/`horde_spawns` which already suppress it).
- `rubble` (as a def array key) — `_strip_lava_overlaps` defensively strips
  a `"rubble"` array if a level ever authors one, but `_build_rubble` itself
  never reads `def.get("rubble")` — the visible rubble clusters it places are
  always procedural (wall-corner scatter), not def-driven. If a level ever
  needs authored rubble placement, this key does not currently do anything.

## Maintenance

Adding a new level-def key: add a row to the relevant table above, **and**
if the key is a `pos`/`size`/ground-plane float, add it to the matching loop
in `LevelDefs._scaled()` (`scripts/levels/level_defs.gd`) — otherwise it
spawns at unscaled (pre-×1.4) coordinates on every level that doesn't pin
`"world_scale": 1.0`.
