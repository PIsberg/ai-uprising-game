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

### AudioBus and SoundSynth
<!-- lat: { "require-code-mention": true } -->
All sound effects in the game are procedurally synthesized using `SoundSynth`. Real audio files can be placed at `assets/audio/samples/<sound_id>.{ogg,wav,mp3}` to transparently override these procedurally generated sounds.

### GraphicsSettings
<!-- lat: { "require-code-mention": true } -->
Manages graphics quality presets (LOW, MEDIUM, HIGH, ULTRA). These presets drive:
* Viewport quality and post-processing quality
* Environment settings (shadows, light counts)
* Light budgets consumed by the level builder
