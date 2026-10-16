# AI Uprising

![AI Uprising title screen](docs/screenshots/title_screen.png)

**[Play it on itch.io](https://gotrex.itch.io/ai-uprising)** (Windows and Linux builds) · or run it from source with Godot 4.7, below.

A 3D first-person shooter built in **Godot 4.7** (Forward+). The machines we trusted turned on us. Fight back through a 24-level campaign of rogue drones, androids, spiders, shielded brutes, kamikaze seekers, leaping skitters, siege mechs and towering bosses, including hazard arenas fought on catwalks over a molten sea and a flooded reactor, against an enemy AI that adapts to how you play, narrated by comic-book briefings and scored by adaptive synth music.

Nearly everything in the game (geometry, enemies, weapons, FX, audio, cutscenes) is **generated in code or from compact data**, so the whole project is small, version-controllable as text, and validated headlessly.

---

## Gallery

In-engine captures from the game, HUD included.

### Sectors

|  |  |
|:--:|:--:|
| ![Anthropic Constitutional Vault](docs/screenshots/constitutional_vault.png) | ![Neon Arcade](docs/screenshots/neon_arcade.png) |
| **Constitutional Vault**: ceiling strips and server racks mirrored in a wet floor | **Neon Arcade**: magenta light lanes, holding the broadcast booth |
| ![Frostbreak Relay](docs/screenshots/frostbreak_moonlit.png) | ![Sunblind Expanse](docs/screenshots/sunblind_golden_hour.png) |
| **Frostbreak Relay**: a moonlit blizzard, a robot rounding the cover | **Sunblind Expanse**: golden hour over the desert relay |
| ![Mistral Cryo-Core](docs/screenshots/mistral_cryo_core.png) | ![First Contact: The Hollow](docs/screenshots/the_hollow.png) |
| **Mistral Cryo-Core**: venting coolant pumps under the reactor lamps | **The Hollow**: an off-world contact beacon on a toxic green plain |
| ![Maple Grove Plaza](docs/screenshots/maple_grove_colossus.png) | ![Tidecore Basin](docs/screenshots/moonlit_reactor.png) |
| **Maple Grove Plaza**: a sunset street seconds before GOLIATH-IX arrives | **Tidecore Basin**: a night firefight in the flooded reactor under the milky way |

### Combat

|  |  |
|:--:|:--:|
| ![GOLIATH-IX sky-drop](docs/screenshots/sky_boss.png) | ![The Assembly: an elite spawn](docs/screenshots/assembly_elite.png) |
| **First boss**: GOLIATH-IX makes planetfall on its retro-rockets | **Elites**: a SHIELDED elite, armour you flank or out-gun |
| ![Melee execution](docs/screenshots/execution.png) | ![Adrenaline surge](docs/screenshots/adrenaline.png) |
| **EXECUTED!**: melee a robot under 40 HP and it dies outright | **ADRENALINE!**: near death, bullet-time and a heal for a comeback |

### Story and between levels

|  |  |
|:--:|:--:|
| ![Comic intro](docs/screenshots/comic_intro.png) | ![Briefing: GOLIATH-IX](docs/screenshots/briefing_goliath.png) |
| **Comic intro**: the night the helper robots turned | **Briefings**: every level opens on a comic panel, the act and the 03:14 trace log |
| ![Briefing: ARCHON](docs/screenshots/briefing_archon.png) | ![Resistance Armory](docs/screenshots/armory.png) |
| **The Mind Cathedral**: the trace ends at ARCHON | **Armory**: upgrade tracks, field supplies and weapon mods bought with run score |
| ![Enemy codex: Ravager](docs/screenshots/codex_ravager.png) | ![Level editor](docs/screenshots/level_editor.png) |
| **Enemy Codex**: every hostile you have met, turning in 3D with its counters | **Level editor**: build levels as data with a live marker preview and one-click playtest |

---

## Running the game

**Requirements**
- [Godot Engine 4.7+](https://godotengine.org/download) — *Standard* build (GDScript; not the .NET/C# build)
- A GPU that supports the **Forward+** renderer

**Play**
1. Install Godot 4.7+.
2. Launch Godot → **Import** → select this repo's `project.godot` → **Import & Edit**.
3. Press **F5**. The main scene (`scenes/ui/main_menu.tscn`) opens → **Begin Operation** → pick a difficulty.
   - The mouse is captured on play; press **Esc** to pause / release it.

**From a terminal** (Godot on `PATH`):
```bash
godot --path . --import      # one-time asset import
godot --path .               # run the game
```

**Headless validation** (no window — used heavily during development to load-test scenes):
```bash
godot --headless --path . --import
godot --headless --path . res://scenes/levels/level_gpt.tscn --quit-after 120
```

### Run outside Godot (standalone build)

To play **without the Godot editor**, export the project to a self-contained executable. The repo already ships export presets (`export_presets.cfg`) for **Windows Desktop** and **Linux**; both embed the game data (PCK) into a single file and exclude the `tests/` probes.

**One-time setup — export templates** (the engine code that gets bundled into your build). They must match your Godot version (4.7.x):
- In the editor: **Editor → Manage Export Templates → Download and Install**, *or*
- CLI: `godot --headless --install-export-templates` (4.7+), or download the `.tpz` from the Godot site and install it.

**Export from the terminal** (headless — no editor window):
```bash
godot --headless --export-release "Windows Desktop" build/windows/ai-uprising.exe
godot --headless --export-release "Linux"           build/linux/ai-uprising.x86_64
# use --export-debug instead of --export-release for a build with a debug console
```
*(Or in the editor: **Project → Export → pick a preset → Export Project**.)*

**Run the standalone build** — no Godot needed; the executable is fully self-contained, so you can copy/ship just this one file:
```bash
# Windows
build\windows\ai-uprising.exe
# Linux (mark executable first if needed)
chmod +x build/linux/ai-uprising.x86_64 && ./build/linux/ai-uprising.x86_64
```
Builds land in `build/` (git-ignored) as a single self-contained file (~250 MB, game data embedded) — verified to boot standalone with no editor. To see logs, run it from a terminal with `--verbose`, or export a `--export-debug` build.

---

## Controls

| Action | Keyboard / Mouse | Gamepad |
|---|---|---|
| Move | `WASD` | Left stick |
| Look | Mouse | Right stick |
| Sprint | `Shift` | L3 |
| **Dash** | `Q` | — |
| **Slide** | Sprint + `Ctrl` while running | — |
| Jump | `Space` | A |
| Crouch | `Ctrl` | B |
| Fire | `LMB` | RT |
| Aim (ADS) | `RMB` | LT |
| Reload | `R` | X |
| Grenade | `G` | Y |
| Cycle grenade type | `H` | — |
| Switch weapon | `1`–`4` / wheel | LB / RB |
| Interact / pick up | `E` | X |
| Flashlight | `L` | D-pad up |
| Night vision (once you find the goggles on GPT or SUBLEVEL) | `N` | D-pad down |
| Pause | `Esc` | Start |

**Testing cheats** (type the word — no console needed): on the main menu, type **`warp`** for a direct level-select that also unlocks the full bestiary and arsenal; **in-game**, type **`god`** to toggle invincibility (tops you off to full health), and type it again to turn it off.

Sensitivity, FOV, invert-Y, framerate cap, graphics tier (Low/Medium/High/Ultra), and master/SFX/music volume are all in **Settings** (main menu and in-game pause). It also includes independent toggles for advanced features (GPU Particles, Volumetric Noise Shafts, Triplanar Damage, Puddle Ripples, and Advanced Post-Process FX), which persist to `user://settings.cfg`.

---

## What's in it

- **24-level campaign** through themed sectors (GPT Foundry, Gemini Nexus, Mistral Cryo-Core, Maple Grove suburbs, a convoy rail-ride, Claude Vault, GROK Black-Site, Skyhold Command, the alien Hollow, Frostbreak, Sunblind Expanse, Neon Arcade, up to ARCHON's Mind Cathedral) — plus two **hazard arenas**, the **Vulcan Forge** molten sea and the **Tidecore Basin** flooded reactor, where you balance on narrow catwalks over a sea that cooks you if you fall in. Each opens with a **comic briefing** and is gated by **task-based objectives** behind an animated **portal**: clear hostiles or hit a kill quota, find a keycard (some of them hallucinated), destroy a core, collect data shards, hack a terminal, plant charges, survive an assault, hold a zone, **assassinate a high-value target**, haul the stolen weights to an uplink, throw kill switches against a watchdog clock, escort an ALIGNED robot out, anchor a path across generated terrain, or reach extraction before a purge.
- **Weapon mods** — four Armory mods change what a hit does: CHAIN ARC jumps to the next robot, THERMITE sets robots burning, RICOCHET bounces wall hits into robots behind cover, and OVERRIDE turns a robot you drop under 25% to your side. One per hitscan or beam gun, refit for free.
- **13 wieldable weapons** — the starter *M9 Sidearm*, pulse rifle, shotgun and *.50 Maelstrom* magnum, then a heavy/energy tier: *Tesla* beam, *Arc-Coil* burst, *MK-VII Longshot* sniper, *Plasma*, piercing *Gauss Lance*, homing *Swarm Launcher*, chain-lightning *Tempest Coil*, rocket *Devastator*, and the *OMEGA-X Annihilator*. Hitscan & projectile, ADS, recoil, charge/volley/slug alt-fires, per-weapon viewmodels, and piercing / splash / cluster / homing / chain-lightning mechanics — plus **four grenade types** (frag, a *Vortex* gravity well that herds a pack into one knot, EMP, and a *HIJACK* spike that turns the nearest robot to your side for 12 s; cycle with `H`).
- **52 hostiles** including **7 bosses** — the recon **drone**, infantry **android**, leaping **spider**, hopping **skitter** swarms, heavy **mech**, suppressing **gunner**, **sniper** sentry (charged beam), kamikaze **seeker**, flying **raptor**, shielded **bulwark brute**, healer **mender**, shield drone **aegis**, the fierce **Ravager** (a leaping ground-slammer) and **Warmech** (a long-range siege walker), the robotic-fish **Angler Unit** of the flooded basins, and a late wave of AI-themed machines (**DEEPFAKE**, **FORK BOMB**, **OVERFITTER**, **ATTENTION HEAD**, **MIXTURE OF EXPERTS**, **REWARD MODEL**, **DIFFUSION**, **ROLLBACK**, **QUANTIZER**) — up to the **TERMINATOR**, sky-dropping **GOLIATH-IX**, hovering **OVERSEER**, the arm boss **MANUS**, **BEHEMOTH-X**, **PROMETHEUS-0** and **ARCHON**. Every hostile has a discoverable **bestiary** entry, and the elite-affix system can up-tier any spawn (shielded / volatile / swift / warden / splitter).
- **Adaptive AI Director — the enemy *learns you*.** The rogue AI is an intelligence, so it fights like one: a director quietly profiles **how you play** — camp or keep moving, brawl up close or snipe from range, headshot rate, which gun you lean on — and **counters it** through the Elite affix system. Snipe from afar and it fields **SWIFT** rushers to close the gap; out-aim it and it fields **WARDEN** units you can't stagger (so you must *dodge*, not suppress); spam one weapon and it fields **SHIELDED** armour that shrugs it off. The overlord's taunts read your actual behaviour back to you (*"You like your distance. I'm closing it."*, *"The Shotgun again. I've patched for it."*). The per-level read resets each sector, but **the overlord remembers you across runs**: every cleared level is folded into a long-term dossier, so the swarm comes pre-adapted, a gun you lean on for three levels gets a firmware **countermeasure** (85% damage until you rotate off it), and the overlord opens levels by citing your deaths, your killers and your habits.
- **Game feel** — trauma camera shake, dynamic FOV, dash/slide, recoil, tracers, muzzle flash & smoke, ejected casings, surface-aware impacts, **bullet-hole + scorch decals**, debris, oil/spark sprays on robots, hit-stop, enemy flinch/stagger/last-stand, death topples.
- **Premium Graphics Upgrades (Forward+)** — GPU-accelerated sparks and debris with rigid body collision physics, volumetric noise-animated light shafts (god-rays), triplanar metal shell shading on robots displaying exposed glowing electrical damage grids, dynamic hexagonal-grid energy shields with real-time hit ripple distortion on the Brute and Archon boss, procedural wind waves & concentric rain drip puddles, and anamorphic blue/cyan lens flares combined with fisheye speed-warp barrel distortion during high-velocity dashes/sprints. **Godot 4.7** adds soft **AreaLight3D** ceiling luminaires, HDR-punch emissives, improved clearcoat metal, and velocity-stretched GPU particles.
- **Mood** — themed per-level lighting + fog, cinematic post (vignette / chromatic aberration / film grain / sharpen), AgX tonemap, glow, SSAO/SSIL/SSR, soft shadows, ambient dust, **adaptive combat music** (layered: exploring you hear a bed and a faint lead, a fight brings in the drums and lead, a RAMPAGE streak or a boss adds a hot sixteenth line), and an "area cleared" slow-mo.
- **Cutscenes** — a **comic-panel story intro** (peaceful green-eyed helper robots → the signal → they arm and turn red) and a reusable, choreographed cutscene system used for the per-level briefings, which preview each level's *new* hostiles before you drop in.
- **One story, start to finish**: the campaign is a six-act trace of the 03:14 command back to whoever sent it. Every comic briefing carries the act, a red thread through all 24 levels and a trace-log card saying what the last level uncovered (`scripts/systems/story_arc.gd`).
- **Meta & tools** — an interactive holographic **campaign map** (serpentine route, per-sector intel panel listing each level's hostiles + objective, boss markers, mouse *and* keyboard/controller navigation); a turning-3D **enemy codex** unlocked as you meet each hostile (strengths, weaknesses, counter-weapons); a **weapon codex** detailing every gun's class, stats and role with comparison bars; a between-levels **Armory** shop where run score buys permanent weapon upgrades *and* consumable field supplies (ammo / grenades / health applied on your next deploy); a **Gun Range** + **Horde** survival sandbox; a **Daily Op**, one seeded level a day (the same for every player on that date) on HARD with that day's directive, tracking the day's best score and a streak of consecutive days; and a built-in **level editor** (`--editor`) that authors levels as plain data with a live marker preview, full gizmos, and one-click playtest.
- **Systems** — EASY/NORMAL/HARD scaling, save/checkpoint + Continue, score combos & end-of-level grade, kill feed, radar, objective waypoint, boss bar, directional damage indicator, first-encounter coaching toasts, an accessibility **screen-shake** scale, 4-tier graphics (LOW/MEDIUM/HIGH/ULTRA) that actually change render scale/AA/shadows/effects, and full keyboard-mouse **and** gamepad support.

---

## How it's built

| | |
|---|---|
| **Engine** | Godot 4.7, Forward+ renderer |
| **Language** | GDScript (statically typed; the project compiles with warnings-as-errors) |
| **Art** | Primitive meshes assembled + tinted in code/scenes, plus **CC0 low-poly models** (Quaternius robots, Kenney blaster kit) and CC0/CC-BY PBR textures — all listed in `CREDITS.md` |
| **Audio** | 100% procedural — `SoundSynth` generates every sound (guns, impacts, music, ambience, UI) as `AudioStreamWAV` at startup (a music theme as four synced stems in an `AudioStreamSynchronized`); real samples can override them |
| **Design philosophy** | Data-driven & code-built: levels are dictionaries, enemies/weapons/FX/cutscenes are built at runtime, so content is compact text and headless-testable |

**Autoloads (singletons)** — `scripts/autoload/`:
- **`GameState`** — campaign flow (`CAMPAIGN` order, `go_to_level`/`load_level`), score + kill-streak combos + end-of-level grade, the per-level **task** checklist, difficulty config + level scaling, save/checkpoint (`user://savegame.cfg`), and hit-stop.
- **`SoundSynth`** — synthesizes all audio procedurally into a stream table on `_ready`.
- **`AudioBus`** — Master / Music / SFX buses, a 3D player pool, plays synth-or-sampled sounds, themed music per level, and **adaptive combat intensity** (fades the theme's bed/drums/lead/hot stems with the fight).
- **`GraphicsSettings`** — LOW/MEDIUM/HIGH/ULTRA quality tiers (render scale, AA, shadow filtering, screen-space effects) plus FOV, sensitivity, invert-Y, FPS-cap, and independent toggles for advanced GPU particles, volumetric light shafts, triplanar robot damage, puddle ripples, and advanced post-processing.
- **`AIDirector`** — the **adaptive enemy intelligence**: profiles the player's playstyle (mobility, engagement range, accuracy, headshot rate, weapon focus) from the same shot/hit events the grade tracks, and feeds that read into Elite affix selection (the swarm counters how you fight) and the overlord's taunts. The level read resets each level; a long-term dossier (`user://overlord.cfg`) carries it across runs.

---

## How it works

### Level pipeline (data-driven)
A campaign level scene (`scenes/levels/level_<id>.tscn`) is just three nodes: a **`LevelBuilder`** (`scripts/levels/level_builder.gd`), a **Player**, and a **HUD**. The builder reads a single dictionary for that level from **`LevelDefs`** (`scripts/levels/level_defs.gd`) and constructs everything at runtime: themed sky/fog/lighting + post, floor/walls/cover (compact cover blocks are **breakable**: they crack, shatter into shrapnel and rubble, and the navmesh rebakes around the gap), buildings/ramps/platforms, **breakable props**, accent strips, ambient dust, pickups & weapons, enemy **spawners** (immediate or proximity-triggered), the gated exit **Portal**, and the level **tasks** — then bakes a `NavigationMesh` so ground enemies can path. Adding a level = a new dict entry + a 3-node scene + one line in `GameState.CAMPAIGN`.

### Level editor
Because levels are just data, a built-in **level editor** (`scripts/editor/level_editor.gd`, launched with `--editor`) is a visual front-end for it: place enemies / props / structures / lights with click-drag **gizmos** and Blender-style `G`/`R`/`F` keys against a live **marker preview** (with a translucent placement ghost and a live coordinate readout), tune the whole environment, manage the campaign order, and **one-click playtest** in the real game. It saves `.lvl` files and can export a level straight back to a `LevelDefs` entry. A headless self-test (`--editor-selftest`) covers it end to end.

### Objectives & the portal
Each level registers a **task checklist** with `GameState` (`kill_all`, `kill_quota`, `key`, `destroy_core`, `collect_shards`, `hack_terminal`, `sabotage`, `survive`, `hold_zone`, `assassinate`, `generative_zone`, `haul`, `kill_switch`, `escort`, `escape`; each key is documented in `docs/LEVEL_DEF_KEYS.md`). The exit **`Portal`** (`scripts/systems/portal.gd`) stays sealed (and shoves the player back with a message) until every task is done, then unlocks; the HUD shows the checklist live and an "area cleared" slow-mo fires on the final kill.

### Enemies
All enemies extend **`EnemyBase`** (`scripts/enemies/enemy_base.gd`), a `CharacterBody3D` with a state machine (`IDLE → PATROL → ALERT → CHASE → ATTACK → STAGGER → DEAD`), perception (sight cone + hearing + squad alerting), navmesh pathing with a straight-line fallback, and shared reactions: hit-flash, **flinch & poise/stagger**, **oil/spark sprays**, wounded "last stand," battle-damage smoke/sparks, and a death **topple + lasting scorch**. Each archetype subclasses it and overrides movement/attack — e.g. the drone & seeker fly (`_apply_gravity`/`_move_toward` overrides), the spider does a telegraphed **leap-pounce**, the sniper charges a beam you dodge by breaking line of sight, the brute's **frontal shield** absorbs damage via a `modify_incoming_damage` hook on `Damageable` (so you must flank), and bosses use the HUD boss bar with phase-scaled attacks.

### The Adaptive AI Director
The premise is that you're fighting an *intelligence*, so the enemy doesn't just scale — it **adapts to you**. **`AIDirector`** (`scripts/autoload/ai_director.gd`) builds a live profile of your playstyle from events the game already fires:
- **mobility** — sampled from your ground speed (camper ↔ runner),
- **range_pref** — the distance of your hits (point-blank brawler ↔ long-range sniper),
- **accuracy** & **headshot_rate** — from `register_shot` / `report_player_hit`,
- **weapon focus** — which gun you favour.

That read feeds two systems. `Elite.maybe_apply` asks the director for a **counter affix** so ~70% of elite spawns are chosen to punish your current style — precise aim → **WARDEN** (unstaggerable, forces dodging), fighting at range → **SWIFT** (rushers close the gap), one-weapon reliance → **SHIELDED** (armour that resists it). And the HUD's overlord taunts pull **profile-aware lines** that name what you're doing. Below a small sample threshold the director stays neutral (random affixes, generic taunts) so a fresh level never pre-judges you; the profile resets on every `reset_level_stats`. Logic is unit-checked headlessly by `tests/ai_director_probe.tscn`.

**The dossier (long-term memory).** Each cleared level's read is folded into `AIDirector.dossier` (an exponential blend, newest level weighted `DOSSIER_ALPHA` = 0.35) and persisted to `user://overlord.cfg` across levels, runs and restarts. It also counts runs, deaths and which robot killed you, but a death teaches it nothing, so a player stuck retrying a level is never escalated against. Three effects: while a level is still calibrating, `counter_affix()` counters the dossier once two levels have been folded; a weapon whose blended shot share reaches 0.45 after three folded levels is the **countermeasure** weapon, and `Weapon.eff_damage` multiplies its damage by 0.85 (announced in the patch notes and by a HUD toast when you draw it; rotating off it lifts it within two levels); and the HUD greets each level with a line from `memory_lines()`. A game booted from `res://tests/` or `res://tools/` keeps the dossier in memory only, so probes never read or write a player's file. Settings > **Wipe Overlord Memory** (two presses) resets it. Covered by `tests/overlord_memory_probe.tscn`.

### Weapons
A weapon is a **`WeaponData`** resource (`.tres`: damage, fire mode, recoil, ammo, projectile/hitscan, pierce, FX, sounds) plus a viewmodel scene driven by `weapon.gd`. `weapon.gd` handles the firing ray/projectile, headshots, piercing, recoil, reloads, ADS, and all the muzzle/tracer/impact/heat FX. A **`WeaponManager`** on the player holds the arsenal and carries unlocked weapons across levels.

### Cutscenes
**`CutscenePlayer`** (`scripts/cutscene/`) is a reusable cinematic runner: a depth-of-field camera that eases through a list of *shots* (data: position/look + duration + subtitle), over letterbox bars, a vignette/grain post overlay, fades, title cards, screen flashes, camera shake, and per-shot **action callbacks** for choreography. The **intro** and every **level briefing** are built on it; briefings are generated from `LevelDefs` (themed lighting, a parade of the level's hostiles with dossiers — flagging ones you haven't seen as *NEW* — and the objective).

### HUD & feedback
`scripts/ui/hud.gd` drives the dynamic crosshair, ammo, hit markers, floating damage numbers, kill-confirm, kill feed, radar, objective waypoint, boss bar, low-health vignette, directional damage indicator, the combo readout, and the end-of-level grade — and polls combat state to cue the adaptive music.

### Development workflow
Because content is code/data, it's validated **headlessly**. Every feature ships with a probe in `tests/` (a `.gd` + `.tscn` pair) that drives the real game logic and prints `RESULT PASS` or `RESULT FAIL`; `tools/run_tests.sh` (or `tools/run_tests.ps1` on Windows) runs the suite listed in `tools/probes.txt`, and CI runs it on every push. Probes that need a window save rendered PNGs for visual confirmation instead; `tests/README.md` indexes them all.

---

## Project layout

```
project.godot          # engine config: input map, render, physics layers, autoloads
scenes/
  ui/                  # main_menu, hud, campaign_map, encyclopedia (bestiary)
  editor/              # built-in level editor
  player/              # player + viewmodel
  weapons/             # 13 weapons + projectiles + 4 grenades
  enemies/             # 52 enemy/boss scenes
  levels/              # level_<id>.tscn (LevelBuilder + Player + HUD)
  cutscene/            # comic_intro, level_comic_briefing (+ Armory shop)
  props/ pickups/ fx/  # breakable props, pickups, impact/explosion/tracer FX
scripts/
  autoload/            # GameState, AudioBus, SoundSynth, GraphicsSettings, AIDirector
  player/ weapons/     # player controller, weapon + weapon_data + manager
  enemies/             # enemy_base + one script per archetype
  systems/             # damageable, portal, objective devices, pickups, spawner, enemy_codex
  levels/              # level_builder, level_defs
  editor/              # level editor (data + gizmos + .lvl save/playtest)
  cutscene/ ui/ fx/    # cutscene player + briefings, HUD/map/codex/armory, FX
shaders/               # post_process, crt_screen, night_sky, radar_sweep, …
assets/                # materials, PBR textures, audio (sample-override dir), models, environments
docs/                  # design docs, level_editor_spec, screenshots/ (README gallery)
```

**Physics layers:** 1 `world` · 2 `player` · 3 `enemy` · 4 `player_projectile` · 5 `enemy_projectile` · 6 `pickup` · 7 `trigger` · 8 `firewall` (the `firewalls` def key: an energy sheet only the player collides with; robots, rounds and grenades pass).

---

## Extending

- **Real SFX/music** — drop `assets/audio/samples/<sound_id>.{ogg,wav,mp3}`; it transparently overrides the synth.
- **New weapon** — author a `WeaponData` `.tres` + a viewmodel scene; place it via a level's `weapon` / `extra_weapons` pickup.
- **New enemy** — subclass `EnemyBase`, build a minimal scene (CharacterBody3D + `Damageable` + `NavigationAgent3D`), register it in `LevelBuilder.ENEMY_SCENES` and add a bestiary entry in `EnemyCodex`.
- **New level** — use the built-in **level editor** (`--editor`) to place everything visually and save a `.lvl`, *or* hand-author a dict in `LevelDefs` + a 3-node `level_<id>.tscn` + a line in `GameState.CAMPAIGN`.
- **New cutscene** — subclass `CutscenePlayer`, override `_build_set()` / `_shots()` / `_on_finished()`.

---

## Credits & license

Third-party CC0 / CC-BY assets (ambientCG PBR textures; one Sketchfab boss model) are listed in **`CREDITS.md`**. All code, design, levels, FX, and procedural audio are original. The faction sectors are affectionate parodies named only by colour/theme — no real logos or assets.

Copyright © 2026 Peter Isberg, Deversity AB. All rights reserved.
