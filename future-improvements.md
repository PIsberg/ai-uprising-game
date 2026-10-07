# Future Improvements

A living backlog of work left to do, roughly prioritised. Each item notes **why**
it matters and **where** it plugs into the codebase. Tags:

- 🎮 **needs playtest** — requires a human playing for feel/balance judgment
- 🎨 **needs assets** — requires art/audio I can't generate
- 🤖 **autonomous** — I can build and verify this headlessly on my own
- ♿ **accessibility**

---

## 1. Highest value

### Balance & feel pass 🎮
The whole game is verified *by probe* ("it builds, it spawns, the task completes") but
never tuned *by feel*. Play the 20-level campaign and report:
- Difficulty curve — spikes, dead spots, the new hazard arenas (are they fun or just annoying?).
- Weapon viability — do all 15 guns have a niche, or do 3 dominate? (cross-check the Weapon Codex bars).
- AI Director fairness — do its counters feel clever or cheap? Tune thresholds in `scripts/autoload/ai_director.gd` (`counter_affix`, `MIN_SAMPLES`, the 0.7 bias in `Elite.maybe_apply`).
- Hazard damage / walkway widths in `scripts/levels/level_defs.gd` (`_lava_world` / `_water_world`, `_hazard_platforms`).

### Real audio 🎨
Biggest *perceived* polish jump. The synth is good, but real SFX/music samples drop in
transparently via the override hook — `assets/audio/samples/<sound_id>.{ogg,wav,mp3}`
shadows any `SoundSynth` id. Priority ids: weapon fire, impacts, explosions, the music tracks.

### Weapon-feel distinctness 🎮🎨
Make each gun *feel* different (sound, recoil curve, screen impact), not just stat-different.
Tune `WeaponData` `.tres` + `weapon.gd` recoil/FX; needs playtest to judge.

---

## 2. Content & depth

### Bespoke briefings for the hazard levels 🤖
`_lava_world` / `_water_world` use the generic data-driven briefing. Give them custom
comic-panel briefings like the older levels (`scenes/cutscene/level_comic_briefing.tscn`,
`assets/comics/`).

### Boss mechanics audit 🎮
✅ **Audited (2026-09-11)** — all 7 bosses escalate with health: COLOSSUS/OVERSEER/TITAN/
ARCHON/SMASHER had 3 HP-keyed phases; TERMINATOR ramps its beam sweep as it is wounded;
MANUS (the one plain HP bar) now has 3 phases too — cooldowns ×1/0.8/0.62 and a phase-3
double finger eruption that leads the player (`tests/manus_phase_probe`). 🎮 Still needs
playtest: whether the MANUS phase-3 cadence is fun or just busy.
✅ **Measured (2026-10-08)** — `tests/boss_phase_probe` drives every other boss's escalation and
found SMASHER's phases were glow-only; it now shortens smash/slam/rake cooldowns ×1/0.8/0.62
like MANUS. 🎮 Needs playtest: whether a 1.5 s smash at low HP is too much in the crucible.

### Meta-progression / replayability 🤖🎮
Beyond the per-run Armory there's no persistent chase. Options: unlockables, a seeded
daily run, a local leaderboard off the existing grade/records system (`GameState.level_bests`,
`records.cfg`), or a challenge-modifier mode.

### The AI Director's player counter-move 🤖
✅ **First cut shipped** — the **EMP grenade** (3rd grenade type) bursts in a radius and
disables robots for a few seconds (`EnemyBase.emp_disable`, `grenade_emp.{gd,tscn}`).
✅ **HIJACK charge shipped** (4th grenade type) — converts the nearest robot to your
side until burnout (`EnemyBase.hijack`, `grenade_hijack.{gd,tscn}`, `tests/hijack_probe`).
✅ **AI patch-notes escalation shipped** — the director's per-level read ships as an
"INTERCEPTED — ROBOT OS PATCH NOTES" terminal card on the next briefing
(`AIDirector.patch_notes`, `GameState._build_patch_notes`, `tests/patchnotes_probe`).
Still open as bigger swings: an overload that turns a robot into a bomb, weapon-disable,
idea #4 "glitch warfare".

### Skirmish events (mid-level pacing variety) 🤖🎮
✅ **Shipped** — rare announced events break up a level's authored rhythm
(`GameState._tick_events`, `tests/events_probe`): ASSASSIN CONTRACT (a hunter
warps in pre-marked as the bounty), SUPPLY FLARE (timed cache beacon, 40s),
GRID SURGE (20s double ultimate charge). Gated off boss/convoy/horde levels,
max 2/level. 🎮 Needs playtest: frequency (75s first / ~90s interval) and
whether more event types are wanted (rogue patrol, jammer, double-bounty hour).

### Nemesis / kill-cam / dismemberment (2026-07-10 pack) 🤖
✅ **Nemesis elites** — the elite that kills you returns named + ranked until you settle
the grudge (`GameState.record_nemesis_killer`, `Elite.apply_nemesis`, `tests/nemesis_probe`).
🎮 Needs playtest: rank-1 stat gains (+45% HP) and the once-per-level spawn cadence.
✅ **Boss kill-cam** — deep slow-mo ramp on boss kills (`GameState.boss_killcam`,
`tests/killcam_probe`). 🎮 Tune KILLCAM_HOLD/DURATION by feel.
✅ **Limb dismemberment** — bone-collapse limb loss + flung wreck chunks at crit damage
and death (`EnemyBase._dismember_limb`, `tests/limbloss_probe`). 🎨 Optional upgrade:
per-chassis limb chunk meshes instead of the generic two-segment servo arm.

---

## 3. UX & accessibility ♿

### More accessibility toggles 🤖
- ✅ **Screen Shake** scale and **Flash Intensity** scale shipped (Settings + pause menu).
- ✅ **Flash Intensity now also scales world light bursts** (muzzle flash, hit/impact pops,
  explosion and grenade detonation lights; steady lights untouched) — `tests/flash_intensity_probe`.
- Colourblind-aware FX/HUD palettes (hazard rings already have a text tag; extend to other colour-only cues).
- Subtitle/damage-number size scaling.
- ✅ **Damage Taken slider shipped** (Settings + pause menu, 50–150%, `GraphicsSettings.damage_taken`, `tests/damage_taken_probe`). ✅ **It counts toward the grade like a tier** (x0.85 at 50%, x1.10 at 150%, named on the debrief next to the tier; `GameState.assist_score_mult`, `tests/grade_assist_probe`, issue #88). Still open: aim-assist for KBM, other modifiers.

### Weapon Codex polish 🤖
- ✅ **Spinning 3D weapon preview shipped** — lifts each weapon's `Viewmodel` node
  into a SubViewport turntable (no `blaster-*.glb` mapping needed; the in-game guns
  are procedural meshes).
- ✅ **Auto-firing preview shipped** — the turntable now fires on a calm cadence,
  spawning each gun's real `muzzle_flash_scene` at the `Muzzle` tip (same
  `tracer_color` tint + `muzzle_scale` size weapon.gd uses) with a recoil kick
  scaled by `recoil_pitch`, and a tinted bloom for beam guns with no flash scene.
  Doubles as a live check that per-weapon FX values are wired right.
- Optional "weapons discovered as you pick them up" gating (needs a persistent
  `discovered_weapons` like the bestiary's `discovered_enemies`).

### In-run quick reference 🤖
✅ **FIELD MANUAL shipped** — a pause-menu overlay (no scene change) listing the threats alive
on the current level (discovered ones with weaknesses + counter-weapons, undiscovered as
"unidentified signature") and your arsenal with each gun's effective band
(`hud.gd` `open_field_manual`, `tests/field_manual_probe`).

---

## 4. Tech & quality 🤖

- **Performance** — profile big hordes / low-end GPUs (`Last Stand` horde mode is a good stress test); verify the 4 graphics tiers scale cost as intended.
- **Wider probe coverage** — the suite (`tools/run_tests.sh`) now covers objectives, hazards, loot, teaching, director, elites, **weapon stats**, **EMP**, **combat-damage math** (range falloff, headshots, pierce — measured in-engine, `tests/damage_math_probe`) and **save/load round-trip** (`tests/save_probe`, which caught Armory supplies being lost on Continue). **Continue-from-every-level** now gated by `tests/continue_sweep_probe`. Every boss's wounded escalation is gated by `tests/boss_phase_probe` (MANUS by `tests/manus_phase_probe`).

---

> Maintained alongside the work. When an item ships, delete it here and note it in the
> commit/PR. The verification philosophy stays the same: build it, prove it headlessly.
