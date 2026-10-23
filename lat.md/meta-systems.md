# Meta Progression and Codex Systems

This document describes the out-of-mission systems: the campaign progression route, the armory upgrade shop, and the 3D codex archives.

## Campaign Map
<!-- lat: { "require-code-mention": true } -->
The campaign map interface (`scripts/ui/campaign_map.gd`) renders an interactive holographic sector map:
* **Progression Route:** Serpentine mission nodes tracing the human resistance path toward the central AI core.
* **Sector Intel:** Displays hostile unit compositions, primary/secondary objectives, environmental hazard ratings, and boss encounters before deployment.
* **Navigation & State:** Supports mouse, keyboard, and controller navigation; synchronizes completed sectors and unlocked routes with `GameState.CAMPAIGN`.

## Personal Board
<!-- lat: { "require-code-mention": true } -->
Every campaign level keeps the player's top `GameState.BOARD_SIZE` (5) clears, ranked by the 0-100 performance points behind the letter grade, so a replay can beat a run with the same letter:
* **Entry:** `grade_level` calls `record_run(lid, {points, grade, time})`, which stamps the difficulty and date, inserts best first (a tie goes below the run already there), cuts at 5, writes `records.cfg` `[board]` and returns the 1-based place (0 off the board). UPRISING sectors, Daily Ops and levels with no id are not entered, and their stats carry no `board_place`.
* **Display:** the debrief adds `hud.board_line` ("PERFORMANCE 77 · BOARD #2 · TOP 91", "★ #1 PERSONAL BEST" for a first place); the campaign map's sector intel lists the board under the best rank (`campaign_map.board_text`).
* **Path:** `GameState.board_path` (default `RECORDS_PATH`) is where the per-level grades and boards are read and written; `tests/leaderboard_probe` redirects it.

## Story Thread
<!-- lat: { "require-code-mention": true } -->
The campaign's narrative spine lives in `StoryArc.BEATS` (`scripts/systems/story_arc.gd`), one beat per campaign level id:
* **The question:** the intro's 03:14 command; each level is one hop of the trace back to its sender, ARCHON.
* **Beat fields:** `act` (index into `StoryArc.ACTS`, six acts), `tagline` (the briefing's mood line), `trace` (what the previous level uncovered, empty for the first) and `lead` (one line on SECTOR CLEARED, what this level recovered; `StoryArc.lead`, shown by `hud.gd` `_update_lead_block`, not on a Daily Op).
* **Briefing:** `level_comic_briefing.gd` prints `StoryArc.act_header`, the tagline, a red thread bar built from `StoryArc.campaign_acts` and the trace card. The SUBLEVEL reveal cutscene opens on that level's trace.
* **Overlord:** `StoryArc.OVERLORD_LINES` holds three lines per act, none naming ARCHON. `hud.gd` `_opening_line` uses one when `AIDirector.greeting()` is empty, and the ambient drip draws one on 35% of the ticks where the director has no taunt (14% of all ticks once it has a read).
* **Ending:** the credits (`scripts/ui/credits.gd` `_entries`) open with `StoryArc.trace_recap`, every lead in campaign order; the victory broadcast and cutscene captions name the 03:14 order.
* **Endings:** after the victory cutscene, `EndingChoice` (`scripts/cutscene/ending_choice.gd`) asks what to do with ARCHON's last spark: `StoryArc.ENDINGS` SHUT IT DOWN (always), TAKE ITS SEAT (`ENDING_HIJACKS` 3 hijacks in the run) or SET IT FREE (`ENDING_BREACHES` 5 network breaches). `GameState.run_hijacks` / `run_breaches` count them (saved with the run, zeroed by `start_campaign`); locked endings show what they need. The pick is recorded in `records.cfg` `[endings]` (marked SEEN next time) and `EndingChoice.transmission_for` plays that ending's broadcast before the credits. `tests/ending_choice_probe`, `tests/ending_choice_shot` (windowed).
* **Rule:** a new campaign level needs a beat, with acts staying in campaign order. `tests/story_arc_probe` (suite).

## Armory Shop
<!-- lat: { "require-code-mention": true } -->
The Armory (`scripts/ui/armory.gd`) provides a meta-progression shop between combat missions:
* **Score Economy:** Converts player mission score and bounty rewards into credits for persistent equipment investments.
* **Permanent Upgrades:** Six run-long tracks (`Armory.KEYS`): `damage`, `mag` (clip size), `reload`, `blast` (grenade radius), `leech` (heal from damage dealt) and `stamina`.
* **Consumable Supplies:** Three supply keys (`Armory.SKEYS`): `ammo`, `grenades` and `health` (max HP on deploy). These persist for the whole run and are re-applied on every deploy.
* **Weapon Mods:** Four cards (`Armory.MKEYS`) with a gun picker: BUY + FIT buys a mod and fits it to the picked gun; owned mods FIT or SWAP for free. See [[weapons#Weapon Mods]].

## Daily Op
<!-- lat: { "require-code-mention": true } -->
One seeded level a day, outside the campaign (main menu, under Last Stand):
* **Seed:** `GameState.daily_op_for(date)` hashes the local date, so every player gets the same op on the same day: one non-boss campaign level other than the first, and one directive (always rolled).
* **Loadout:** HARD, with `GameState.daily_arsenal(level)`, the guns the campaign hands out before that level (weapon pacing); no Armory upgrades or mods.
* **Isolation:** `start_daily_op` snapshots the run state (`DAILY_RUN_KEYS`); while `daily_op` is set, `load_level` skips the campaign bookkeeping and `save_progress` refuses to write. `end_daily_op` (called by the main menu on every visit) restores the snapshot, so no path out of an op leaves its difficulty or guns behind.
* **Records:** `record_daily_clear` keeps the day's best score and a streak of consecutive days with a clear in `records.cfg` `[daily]`; the win screen shows score, best and streak and returns to the menu (`advance_level` -> `finish_daily_op`). `tests/daily_op_probe` (suite).

## Uprising Mode
<!-- lat: { "require-code-mention": true } -->
A seeded five-sector run with drafted patches, outside the campaign (main menu, under Daily Op):
* **Plan:** `GameState.uprising_plan(seed)` picks `UPRISING_SECTORS` - 1 non-boss campaign levels other than the first, in campaign order, then one boss level. Each sector keeps its own campaign-depth scaling (`campaign_progress` reads the level path) and gets the guns the campaign hands out before it (`daily_arsenal`); the run's arsenal only grows.
* **Draft:** clearing a sector (`advance_level` -> `_uprising_advance`) opens `scenes/ui/uprising_draft.tscn` with three offers from `UPRISING_PATCHES`, rolled from the seed, the sector and the reroll count. A patch is a buff with a cost: its `damage`/`incoming`/`move`/`pickup` multiply into the `directive_*_mult` getters (`uprising_mult`), `upgrade` grants Armory ranks, `lives` adds reboots. Runs roll no combat directive and skip the Armory (`can_buy_anything`): the patches are the build.
* **Reboots:** `UPRISING_LIVES` deaths are forgiven (`_uprising_on_death`); a retry rewinds the score to the sector's entry score (`load_level`). A cleared sector repairs one spent reboot, up to `max_lives`. The next death past the last reboot ends the run after `UPRISING_CLOSE_DELAY`.
* **Compute:** however the run ends (`_close_uprising`, or `abandon_uprising` from the main menu) it banks score / `UPRISING_SCORE_PER_COMPUTE` + `UPRISING_SECTOR_COMPUTE` per sector cleared (+ `UPRISING_CLEAR_COMPUTE` for a full clear) into `records.cfg` `[uprising]`. Compute pays for rerolls; lifetime compute (`earned`) unlocks the patches with an `unlock` threshold.
* **Isolation:** like a Daily Op, `start_uprising` snapshots `DAILY_RUN_KEYS` and `end_uprising` restores them; `save_progress` refuses to write and `go_to_level`/`load_level` skip the campaign bookkeeping. Story cutscenes (`CUTSCENE_FOR_LEVEL`) give way to the plain briefing. `tests/uprising_probe` (suite), `tests/uprising_playtest` (report).

## Telemetry
<!-- lat: { "require-code-mention": true } -->
A local playtest recorder (`scripts/autoload/telemetry.gd`, autoload `Telemetry`); it never sends anything anywhere.
* **When:** `enabled_by_default` is on for a windowed debug run (playing from source) and off headless (the probe suite) and in release exports; `--telemetry` / `--no-telemetry` override either way.
* **File:** one JSON object per line in `user://telemetry/<datetime>.jsonl`, the newest `KEEP_FILES` (50) kept. Events: `session_start`, `level_start` (mode, difficulty, directive, patches), `death` (killer, held gun, position, the hits of the last `RECENT_WINDOW` s), `task`, `breach` (a NETWORK BREACH and its label), `stuck` (a move key held `STUCK_TIME` s on the floor without moving), `level_end` (result clear/left/restart, grade, time, score, health lost by source, shots/hits/kills by weapon, kills by enemy), `session_end`.
* **Names:** damage sources are named by `Damageable.source_label`, the same function the death screen uses, so the report and the recap agree.
* **Report:** `tools/telemetry_report.py` (newest session, a given file, or `--all`) prints per level the attempts, clears, time, deaths by killer, top damage sources, weapon accuracy and kills, and stuck spots. `tests/telemetry_probe` (suite).

## Achievements
<!-- lat: { "require-code-mention": true } -->
Twenty local unlocks for the game's signature moments (`scripts/autoload/achievements.gd`, autoload `Achievements`), listening to GameState signals only.

* **Defs:** `Achievements.DEFS` (id, title, desc, optional `count`); lifetime counters (`COUNTERS`: kills 500, executions 10, bounties 5) unlock at their target.
* **Signals:** besides the existing combat ones, GameState emits `robot_hijacked`, `network_breached`, `ending_recorded`, `uprising_closed` and `daily_completed` for them.
* **Store:** `user://achievements.cfg`; a run booted from `res://tests/` or `res://tools/` never reads or writes it (AIDirector's rule). An unlock pops a gold toast once and is mirrored to Steam if a `Steam` singleton exists (none today).
* **Menu:** the main menu's Achievements button shows the count and opens `list_overlay()`. `tests/achievements_probe` (suite), `tests/achievements_shot` (windowed).

## Machine Feed
<!-- lat: { "require-code-mention": true } -->
The rogue AI livestreams the fight to its robot network; the audience's chat runs down the left of the HUD (`scripts/ui/machine_feed.gd`, lines in `scripts/systems/machine_chat.gd`).

* `MachineChat.LINES` holds 12 pools (intro, idle, cascade, execution, meltdown, scrapped, dodge, salvage, rampage, clutch, boss, death), 5 lines each, every one a `strings.csv` key translated into all five languages; `HANDLES` are robot usernames, untranslated.
* `MachineFeed` listens to GameState (`cascade_chain` from `CASCADE_CALLOUT` pops, `execution`, `environmental_kill`, `perfect_dodge`, `rampage_changed`, `adrenaline_changed`, `boss_spawned`, `player_died`); the HUD calls `on_salvage` when a salvage gun is armed. A quiet `IDLE_GAP` (22 s) posts an idle line.
* One post per `MIN_GAP` (1.2 s): a burst of events posts the first, but small talk (`CHATTER`: intro, idle) never blocks an event line, and a death always posts. At most `MAX_LINES` (5) show, each fading after `LINE_LIFE` (7 s); a line never repeats the one its pool posted last.
* Viewers start at `BASE_VIEWERS` + `VIEWERS_PER_LEVEL` x `GameState.level_index`, gain `MachineChat.HYPE` per event (the cascade's x pops, rampage's x tier), lose `DECAY` of the excess every `DECAY_TICK`, and keep `DEATH_KEEP` when you die.
* Off with the Combat Callouts setting (`GraphicsSettings.combat_callouts_enabled`), which also hides the feed. `tests/machine_feed_probe`.
* **ROGUE FORK:** a skirmish event (`GameState._event_rogue_fork`, id `rogue`): `ROGUE_SQUAD` (android, android, drone, gunner) spawns on a ring 1.8 m round a point `ROGUE_SPAWN_DIST` (18 m) from the player and each calls `EnemyBase.go_rogue()` ([[enemies#Collisions and Hijacking]]). `_on_rogue_died` pays `ROGUE_BONUS` (100) only when the source is the player, plus `ROGUE_CONTAIN_BONUS` (300) when no live fork is left, through `rogue_deleted(points, left)` (HUD toast FORK DELETED / FORK CONTAINED). Forks never burn out. `tests/rogue_fork_probe`.
* **CHAT POLL:** the skirmish-event director (`GameState._tick_events`) no longer rolls a due event silently. It opens `_poll` between two different `EVENT_IDS` (`chat_poll_started`), adds a random 3-14 votes to one side every `POLL_TICK` (`chat_poll_votes`) for `POLL_TIME` (8 s, `PLAYING` only, so a pause freezes it), then runs the leader through `_run_event` (`chat_poll_ended`; a tie goes to the first option). The poll counts against `EVENTS_PER_LEVEL` when it opens; `reset_level_stats` drops an open one. The feed draws the tally under its header and posts "CHAT VOTED: <event>". `tests/chat_poll_probe`.

## 3D Enemy Codex
<!-- lat: { "require-code-mention": true } -->
The roster data lives in `scripts/systems/enemy_codex.gd` (`EnemyCodex.ENTRIES`, ordered by
`EnemyCodex.ORDER`); the bestiary screen that renders it is `scripts/ui/encyclopedia.gd`:
* **Discovery Unlocks:** Entries unlock as the player meets each hostile unit; `EnemyBase` calls `GameState.discover_enemy` (kept across runs in `user://bestiary.cfg`), and `GameState.discovered_enemies` gates the entry. Undiscovered robots stay classified.
* **Family Pages:** Robots built on the same model share a page (`EnemyCodex.FAMILIES`: 53 robots on 36 pages). `EnemyCodex.pages()` groups the discovered types, pages and variants in `ORDER`; the screen's Prev/Next walk pages, and a variant bar of one button per discovered robot (or up/down) picks the robot on show. Bosses keep their own page even on a shared body (the OVERSEER is an eye-drone hull). A family id must never equal a type id, or `family_of` pulls that robot in. `tests/codex_family_probe` reads each entry's model file out of its enemy scene, folds Blender forks (`_armed`, `_bladed`, `_siege`, `_fierce`, `_strike`) onto their base, and fails when the table disagrees. Screenshot tools select a robot with `show_type(t)`.
* **Live 3D Model:** Each entry instantiates the robot's real scene on a turntable that spins slowly on its own (`_turntable`, 0.5 rad/s). There is no zoom, wireframe or animation-playback control.
* **Entry Fields:** An entry carries only what the screen shows: `scene`, display `name`, `desc` dossier line, and the `scale`/`y`/`yaw` framing values that pose the model.

## Weapon Codex
<!-- lat: { "require-code-mention": true } -->
The weapon codex (`scripts/ui/weapon_codex.gd`) documents the full arsenal available to the human resistance:
* **Arsenal Roster:** Covers the 14 wieldable weapons in `GameState.WEAPON_ORDER` (weakest to strongest, pistol through OMEGA-X), spanning kinetic firearms, energy beam platforms, and heavy ordnance. Only weapons the player has held appear, plus the `STANDARD_ISSUE` trio.
* **Comparative Statistics:** Normalized comparative bar graphs for raw DPS, effective range, fire rate, recoil severity, and handling.
* **Firing Profiles:** Explains primary hitscan/projectile dynamics, alt-fire charge cycles, and special mechanics (piercing, splash, chain lightning, homing).

## Orbital Strike
<!-- lat: { "require-code-mention": true } -->
A skirmish event (`GameState._event_orbital_strike`, one of the director's eight kinds) that makes the player move or take cover (`OrbitalStrike`).

* A ground circle of `RADIUS` under a thin sky beam tracks the player for `TRACK_TIME`, lagging (`FOLLOW`), so a moving player stays near its edge; then it LOCKS for `LOCK_TIME` (red, pulsing, rising whine) and FIRES: `DAMAGE` to a player inside the circle with nothing (world layer) over their head within `SKY`.
* Robots are never hurt. The node frees itself after the column fades.
* `OrbitalStrike.covered` is also the event's gate: a player already under a roof (an indoor level) gets a SUPPLY FLARE instead, since a strike there could never land.
* `tests/orbital_strike_probe`, `tests/orbital_strike_shot`.

## ARCHON Fine-Tune
<!-- lat: { "require-code-mention": true } -->
The finale trains on the player: ARCHON reads `AIDirector.finetune_plan` once at boot and reshapes every wave around the player's strongest habits.

* The plan takes up to `FINETUNE_HABITS` (3) habits from this level's read once it is calibrated, else from the dossier ([[architecture#Autoloads]]), ranked by how far each sits past its threshold: KEEPS ITS DISTANCE / FIGHTS UP CLOSE (range), NEVER STOPS MOVING / HOLDS ONE SPOT (mobility), LEANS ON THE <gun> (a 45%+ weapon share) and AIMS FOR THE HEAD.
* Range and mobility habits carry roster `swaps` (drones to seekers for a long-range player, androids to seekers for a mover), which `finetune_roster` applies to every other occurrence of a unit so a wave keeps its mix. The strongest habit with an `affix` (crutch: shielded, precise: warden) puts it on up to 2 heavies per wave.
* Boot announces FINE-TUNED ON YOU with the habits, each translated (the crutch line is a format key). The first phase-3 wave sends one `BehaviourClone` of the player ([[meta-systems#Behaviour Clone]]). No history means an empty plan and the stock waves. `tests/archon_finetune_probe`.
## Behaviour Clone
<!-- lat: { "require-code-mention": true } -->
A skirmish event (`GameState._event_behaviour_clone`) that turns the player's own recent play against them (`BehaviourClone`).

* TRAIN: for `TRAIN_TIME` it stands where the player was and records every physics frame of them: feet, camera eye, aim, and whether `GameState.stat_shots` moved.
* REPLAY: for `LIFE` it plays that recording `TRAIN_TIME` behind the player: same path, same aim (a red laser sight shows it), and a world + player hitscan bolt (`SHOT_DAMAGE`, at most one per `SHOT_GAP`) for each recorded shot. `hit_from_inside` makes a player standing where they fired get hit. Robots are never hurt and never block it.
* `HEALTH` damage deletes it (`BONUS`, CLONE DELETED); otherwise it fades after `LIFE`. One at a time: a second roll becomes a SUPPLY FLARE.
* `tests/behaviour_clone_probe`, `tests/behaviour_clone_shot`.
