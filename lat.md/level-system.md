# Level System

Levels in **ai-uprising-game** are defined as structured data dictionaries rather than traditional hand-built scenes.

## Procedural Generation

All level geometry, lighting, navigations, hazards, and enemy spawns are generated procedurally at runtime using configuration profiles.

### Level Definitions
<!-- lat: { "require-code-mention": true } -->
Level profiles are stored in `scripts/levels/level_defs.gd` as dictionaries.
* Profiles define boundaries, lighting styles, obstacle layouts, and wave schedules.
* Documentation of dictionary keys can be found in [docs/LEVEL_DEF_KEYS.md](file:///C:/dev/private/ai-uprising-game/docs/LEVEL_DEF_KEYS.md).

### Level Builder
<!-- lat: { "require-code-mention": true } -->
The `level_builder.gd` script consumes level definition dictionaries and generates the 3D level layout, navigation meshes, lights, and enemy spawn locations at load time.

### Coordinate Scaling
<!-- lat: { "require-code-mention": true } -->
To maintain size consistency:
* All authored level coordinates in definitions are scaled by a multiplier: `WORLD_SCALE = 1.4`.
* Any manual positioning logic must check if the coordinate was already scaled to avoid mixed-coordinate scaling bugs.

### Exceptions
Specifies non-procedural levels and user-made content exceptions.

* **Level 1 (`level_01.tscn`):** The only hand-authored `.tscn` level file in the repository.
* **Custom Editor Levels (`level_custom.tscn`):** Loads user-made custom level layouts saved in `.lvl` formats.
