# Changelog

All notable changes to **AI Uprising** are recorded here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project aims to follow [Semantic Versioning](https://semver.org/).

The version shown in the bottom-right of the main menu comes from
`project.godot` → `application/config/version` (the single source of truth). Bump
it there when cutting a new build, move the `[Unreleased]` notes into a new dated
section below, and re-export.

## [Unreleased]

### Changed
- **Grenades** toned down from near-nuke (~205 dmg over a 6.2 m radius that
  one-shot whole groups) to a strong-but-fair frag (~110 over 4.8 m). The
  GRENADE POWER upgrade still scales up from there.
- **Mistral Cryo-Core** objectives clarified: the coolant-pump tasks are now
  numbered (① pumps → ② core) with a "stand on it" hint, so the required order
  reads at a glance, and the summary spells out the full sequence.

### Fixed
- **End-of-campaign hang/black screen** after the final boss: the victory sequence
  swapped straight to the cutscene, freezing the main thread on a black frame while
  it built its 3D set. It now routes through the loading screen (finale banner)
  like every other scene change, so the build stalls on a proper frame.
- **Headshots and their crit/callout now only trigger on enemy robots** — a
  fallback was awarding a headshot for hitting the upper part of any destructible
  prop or cover object.
- **Hazard readability:** recolored coolant/acid pools and deep-water pools now
  get a pulsing amber warning border, so a lethal cyan pool no longer reads as
  harmless water (Mistral's "step in water, take lava damage" trap).
- Silenced the suburb console spam — 12 `invalid UID ... colormap.png` warnings
  per load, caused by the shared texture's UID being regenerated out from under
  the imported models. Restored the original UID.
- Fixed a `non-equal opposite anchors` UI warning from the Armory scanline
  (`armory.gd`) by sizing it via its bottom offset instead of `.size`.

## [1.0.0] - 2026-07-08

First tracked release. Highlights of the latest polish pass:

### Added
- **Unique boss entrances for every boss.** Each arrival now matches the boss's
  identity, and no two are alike:
  - **PROMETHEUS-0** folds space — a violet rift tears open and it de-rezzes into
    being on a glitch shockwave (previously it reused GOLIATH's sky-drop).
  - **BEHEMOTH-X** boots with a molten wake-slam — reactor flare, warning ring,
    then a deck-quaking double shock ring.
  - **MANUS** drums itself awake — its knuckles rap the floor one by one, each a
    ground-pulse, ending in a rear-up slam.
  - (GOLIATH-IX sky-drop, GROK eruption, OVERSEER portal, and ARCHON's light-column
    assembly were already distinct.)
- **In-game version tag** on the main menu.

### Changed
- **Balance:** the CL-3 Arc Coil — previously the single highest-DPS weapon in the
  game at mid progression — had its fire rate reduced so it fits its tier without
  outclassing every later gun.
- **Visuals:** the GPT Foundry was de-fuzzed from an unreadable green haze into
  crisp neon-noir; the night-sky arenas (Singularity Core, Mind Cathedral, Skyhold,
  Skybridge Uplink) were brightened with moonlight so they read clearly while
  staying moody; the alien "Hollow" green wash was eased back to restore depth.

### Fixed
- **PROMETHEUS-0's phase-blink beam** no longer fires an instant, undodgeable
  on-target sweep the moment it teleports — its charge-tell (designed but never
  wired) now gives a reaction window.
- **MAULER's overload sprint** ("wounded mauler RUNS") now actually applies its
  1.7× speed; it was mutating a spawn-only stat and doing nothing.
- **Armory reset** now clears all six upgrade tracks at the start of a new run,
  not just three.

[Unreleased]: https://github.com/PIsberg/ai-uprising-game/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/PIsberg/ai-uprising-game/releases/tag/v1.0.0
