# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

AI Uprising — a 3D FPS in **Godot 4.7+ (Forward+, GDScript, Standard build — not .NET)**. Nearly everything (level geometry, enemies, weapons, FX, audio, cutscenes) is generated in code or from compact data, so the repo is almost all text and validates headlessly. 4.7 is a hard floor: the lighting uses `AreaLight3D` (4.7-only) and scripts fail to parse on 4.6.

## Commands

Set `GODOT_BIN` (or pass paths explicitly) to a Godot 4.7 console binary. On the primary dev machine it lives at `C:\Users\isber\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe`.

```sh
godot --path .                                  # run the game (main menu)
godot --path . --editor-flag --level <id>       # see GameState._handle_cli_boot for CLI boot options (--editor, --level)
godot --headless --path . --import              # (re)import assets — run once before headless work on a fresh clone

# Full headless probe suite (also: tools/run_tests.ps1 on Windows)
tools/run_tests.sh

# Single probe — every logic probe prints "RESULT PASS" / "RESULT FAIL"
godot --headless --path . --audio-driver Dummy res://tests/<name>_probe.tscn

# Release build (Windows + Linux single-file binaries into build/)
pwsh tools/build_release.ps1        # needs 4.7 export templates; -InstallTemplates downloads them

# Perf measurement (windowed — render stats need a real window)
godot --path . tools/perf_measure.tscn      # fps/draws/prims per level at HIGH tier
godot --path . tools/perf_isolate.tscn      # splits render cost vs script cost
```

## Verification philosophy

**Build it, prove it headlessly.** Every feature ships with a probe in `tests/` (a `.gd` + `.tscn` pair) that asserts behavior and prints `RESULT PASS`. Logic probes run headless; screenshot/`save_png` probes (`*_shot`, `*_screenshot`, `boot_probe`, `dismember_probe`, …) need a window and are excluded from `run_tests.sh`. Add new logic probes to the suite list in `tools/run_tests.sh`.

Probe-writing rules learned the hard way:
- Spawn a floor (`StaticBody3D`, collision layer 1) or every CharacterBody falls forever and position/range assertions lie.
- Sample with **short timer loops** (0.25–0.3 s); one long `SceneTreeTimer` await stalls autoload `_process` ticking headless.
- `get_tree().change_scene_*` frees the probe scene itself — run watchers from a node parented directly under root.

## Architecture

**Autoloads** (`scripts/autoload/`) own all cross-cutting state:
- `GameState` — the hub: game-state machine (PLAYING/PAUSED/…), campaign list (`CAMPAIGN`), score/combo/rampage/ultimate, bounty + skirmish-event directors, nemesis record, ROBOT OS patch notes, save/checkpoints (`user://savegame.cfg`), level task checklist, per-level difficulty scaling, `hit_stop`/`boss_killcam` time dilation. HUD listens to its many signals — features announce via signal + `hud.gd` toast, not direct UI calls.
- `AIDirector` — profiles how the player fights (mobility, range, accuracy, weapon focus); drives Elite counter-affixes, overlord taunts, and the between-level patch notes.
- `AudioBus` / `SoundSynth` — every sound is synthesized; dropping a real file at `assets/audio/samples/<sound_id>.{ogg,wav,mp3}` transparently overrides that id.
- `GraphicsSettings` — 4 quality tiers (LOW/MEDIUM/HIGH/ULTRA). Tier gates live in three places: `_apply_viewport`/`_apply_ss_effect_quality` (global), `apply_to_environment` (per-level env), and `level_builder.gd` (shadowed-light budget `[0,2,6,99]`, area lights, decor density).

**Levels are data, not scenes.** `scripts/levels/level_defs.gd` holds one dictionary per level (floor size, walls, lights, hazards, enemy roster, mission arc); `level_builder.gd` constructs geometry/nav/lighting at load. All authored coordinates are multiplied by `WORLD_SCALE` (1.4) in `get_def` — never mix scaled and unscaled coordinates. `level_01.tscn` is the one hand-authored exception. Custom editor levels are `.lvl` data files loaded through `level_custom.tscn`.

**Enemies.** `EnemyBase` (`scripts/enemies/enemy_base.gd`) is a CharacterBody3D state machine (IDLE/PATROL/ALERT/CHASE/ATTACK/STAGGER/DEAD) with a `Damageable` child node for health. Critical convention: subclasses hardcode stats in `_ready` AFTER `super._ready()`, so elite/difficulty scaling must go through `_health_mult`/`_speed_mult`/`_cooldown_mult` (applied deferred by `_sync_stats`) — writing stats directly pre-add gets clobbered. Several subclasses override `_on_died`/`_state_attack` **without calling super** — hook `hp.died`/`hp.damaged` signals instead of extending those methods. `Elite.apply`/`apply_nemesis` must run **before** `add_child`.

**Collision layers:** 1 = world, 2 = player, 4 = enemies, 8 = grenades. Enemy hitscans/LOS mask world+player; player fire masks world+enemy. `Damageable.apply_damage` blocks enemy→enemy damage unless the two are on opposite hijack sides. A hijacked robot swaps to layer 2 (see `EnemyBase.hijack`).

**Weapons.** `WeaponManager` under the player camera holds `Weapon` instances configured by `WeaponData` `.tres` in `assets/weapons/`; the rack self-sorts weakest→strongest. Grenade types live on the player (`grenade_kinds` in `player.gd`), not in the weapon rack.

**Flow between levels:** level complete → `advance_level` → comic briefing (`level_comic_briefing.gd`, shows intercepted patch notes) → optional Armory → `loading_screen.gd` (threaded load with `use_sub_threads=true`) → level.

## GDScript gotchas that have caused real bugs here

- A **freed instance compares EQUAL to null** but `is`/property access still raise — guard with `is_instance_valid(x)` alone, never `x != null`.
- `Engine.time_scale` near zero breaks tween/timer stepping even with `set_ignore_time_scale(true)` — the kill-cam ramps on wall-clock ms from `_process` instead (see `_tick_killcam`).
- `PackedStringArray` has no `pick_random()`; a parse error anywhere in an autoload silently nils the entire autoload.
- Skinned GLB enemies have no detachable limb nodes — dismemberment collapses bone pose scale (`_dismember_limb`).

## Housekeeping

- `future-improvements.md` is the living backlog: delete items when shipped, note it in the commit.
- `docs/AAA_ROADMAP.md` records completed visual/feel passes and what's still open.
- Keep the loading screen's threaded-load path intact; the big levels' shared robot-model chunk stalls a serialized load for many seconds (reported as a freeze).
