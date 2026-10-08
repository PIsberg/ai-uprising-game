# Game Architecture

This document defines the high-level system architecture of **ai-uprising-game**.

## Autoloads

Autoloads in Godot are global scripts that persist across scene changes. They own all cross-cutting game state and core loop logic.

### GameState
<!-- lat: { "require-code-mention": true } -->
The hub of the entire application. It handles:
* The core game-state machine (`PLAYING`, `PAUSED`, etc.)
* Campaign configuration and lists (`CAMPAIGN`)
* Save files and checkpoints (`user://savegame.cfg`)
* Scores, combos, and ultimate charge rates
* Per-level difficulty scaling and the Bounty system
* CLI boot logic (`_handle_cli_boot`) for debugging and testing

### AIDirector
<!-- lat: { "require-code-mention": true } -->
Profiles player performance and adjusts gameplay dynamics:
* Monitors player behavior (accuracy, movement patterns, weapon preferences)
* Drives Elite enemy affixes based on player profiles
* Triggers overlord/boss taunts
* Generates procedural patch notes presented between levels
* Keeps a long-term dossier (`dossier`, persisted to `user://overlord.cfg`) folded from every level read on level complete and on death (`fold_level`, `note_death`). It pre-adapts `counter_affix` while a level calibrates, picks a `countermeasure_weapon` that `Weapon.eff_damage` scales by `COUNTERMEASURE_MULT`, and feeds the HUD's level-opening `greeting`. `persist` is false when the boot scene lives under `res://tests/` or `res://tools/`, so probes never touch a player's file

### AudioBus and SoundSynth
<!-- lat: { "require-code-mention": true } -->
All sound effects in the game are procedurally synthesized using `SoundSynth`. Real audio files can be placed at `assets/audio/samples/<sound_id>.{ogg,wav,mp3}` to transparently override these procedurally generated sounds.

Numbered takes `<sound_id>_0` .. `_7` become one no-repeat `AudioStreamRandomizer` (`AudioBus._resolve_sample`). Eight ids ship Kenney CC0 takes level-matched to the synth by `tools/import_samples.py` (impacts, footsteps, explosions, the plasma and drone shots); gunshots and music stay synthesized.
* Synthesis runs on a `WorkerThreadPool` task started in `SoundSynth._ready`, menu theme first. `get_stream()` builds any stream that is not ready yet on the calling thread, so early callers never get silence; `AudioBus._start_music` instead waits for `is_ready("music_techno")`, so the first frame is not held up (boot 5.1 s -> 0.8 s to the first frame). The generators must stay pure: no shared state, no scene tree.

### GraphicsSettings
<!-- lat: { "require-code-mention": true } -->
Manages graphics quality presets (LOW, MEDIUM, HIGH, ULTRA). These presets drive:
* Viewport quality and post-processing quality
* Environment settings (shadows, light counts)
* Light budgets consumed by the level builder

It also owns the accessibility display options. Colourblind Mode (`colorblind_mode`) is applied as a 3x3 daltonize matrix (`colorblind_matrix`) by one overlay the autoload owns (`ColorblindOverlay`, CanvasLayer `COLORBLIND_LAYER` 128, above every other layer), so a single pass covers gameplay, the HUD, cutscenes and every menu. It is hidden when Off. Greys are fixed points of the matrix, so neutral text is unchanged. Subtitle Size (`subtitle_scale`, 0.8-2.0) scales timed spoken text; each label reads it through `subtitle_px(base)` when it is built (cutscene subtitles, overlord taunts, the victory transmission).

## CLI Boot Logic
<!-- lat: { "require-code-mention": true } -->
Command-line invocation arguments handled during engine startup (`_handle_cli_boot` in `scripts/autoload/game_state.gd`):
* `--editor`: Boots directly into the built-in 3D Level Editor environment (`EDITOR_SCENE`).
* `--level <path>`: Bypasses menus and loads directly into a authored `.lvl` file via `LEVEL_CUSTOM`.
