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

### Boss mechanics audit 🎮🤖
Verify the 5 bosses have real phases/arena mechanics, not just larger HP bars
(`scripts/enemies/enemy_{terminator,colossus,overseer,titan,archon}.gd`).

### Meta-progression / replayability 🤖🎮
Beyond the per-run Armory there's no persistent chase. Options: unlockables, a seeded
daily run, a local leaderboard off the existing grade/records system (`GameState.level_bests`,
`records.cfg`), or a challenge-modifier mode.

### The AI Director's player counter-move 🤖
✅ **First cut shipped** — the **EMP grenade** (3rd grenade type) bursts in a radius and
disables robots for a few seconds (`EnemyBase.emp_disable`, `grenade_emp.{gd,tscn}`).
Still open as bigger swings: a **hijack** that converts a robot to your side, an overload
that turns it into a bomb, or weapon-disable. (Ideas #3 "AI patch-notes escalation" and #4
"glitch warfare" remain on the table.)

---

## 3. UX & accessibility ♿

### More accessibility toggles 🤖
- ✅ **Screen Shake** scale and **Flash Intensity** scale shipped (Settings + pause menu).
- Extend Flash Intensity to muzzle-flash / explosion-light brightness (currently covers the
  full-screen HUD flashes: damage overlay, low-health vignette, kill-edge).
- Colourblind-aware FX/HUD palettes (hazard rings already have a text tag; extend to other colour-only cues).
- Subtitle/damage-number size scaling.
- Difficulty assists / modifiers (aim-assist exists for gamepad; add for KBM, plus damage-taken sliders).

### Key rebinding UI 🤖
The input map is fixed in `project.godot`. A rebinding screen in Settings
(`scripts/ui/main_menu.gd`) writing to a user config.

### Weapon Codex polish 🤖
- A spinning 3D weapon model on the dossier (map a `blaster-*.glb` per weapon).
- Optional "weapons discovered as you pick them up" gating (needs a persistent
  `discovered_weapons` like the bestiary's `discovered_enemies`).

### In-run quick reference 🤖
Let the pause menu peek the enemy/weapon codex without leaving the level
(needs an overlay rather than a scene change).

---

## 4. Tech & quality 🤖

- **Performance** — profile big hordes / low-end GPUs (`Last Stand` horde mode is a good stress test); verify the 4 graphics tiers scale cost as intended.
- **Cleaner CI logs** — the load-test tolerates benign asset errors (missing `colormap.png` weapon texture, generated `.translation` files). Ship the missing texture or scope the error grep so real errors stand out.
- **Wider probe coverage** — the suite (`tools/run_tests.sh`) now covers objectives, hazards, loot, teaching, director, elites, **weapon stats**, and **EMP**. Still want: combat-damage math (range falloff, headshots, pierce), and save/load round-trip.

---

> Maintained alongside the work. When an item ships, delete it here and note it in the
> commit/PR. The verification philosophy stays the same: build it, prove it headlessly.
