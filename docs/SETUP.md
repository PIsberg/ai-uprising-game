# Setup

## 1. Install Godot 4.3+ (Standard)
- Windows: https://godotengine.org/download/windows — grab "Godot Engine — Standard" (not .NET)
- Extract anywhere. Optionally add to PATH so you can launch with `godot` from a terminal.

## 2. Open the project
- Launch Godot.
- Click **Import** → select `C:\dev\private\ai-uprising\project.godot` → **Import & Edit**.

## 3. First run
- The main scene is set to `scenes/ui/main_menu.tscn`.
- Press **F5** (Play). Click **Begin Operation**.
- Mouse will capture. Press **Esc** to pause / release mouse.

## 4. If something errors on first run
The project uses several script `class_name` declarations. Godot may need to scan once before everything resolves:
- Project → Reload Current Project, or close and reopen.

## 5. Re-baking the navmesh
Enemies use `NavigationAgent3D`. The level's `NavigationRegion3D` contains a navmesh resource. After you change geometry:
- Select the `NavigationRegion3D` node in `scenes/levels/level_01.tscn`.
- Top toolbar → **Bake NavigationMesh**.

## 6. Building a Windows binary
- Project → Export → Add… → Windows Desktop.
- Set the export path → Export Project.
- First time you'll be prompted to download export templates (~600 MB).

## Known limitations of the current placeholder build
- All meshes are CSG primitives; see `docs/ASSETS.md` to swap in realistic models.
- Sound effect AudioStreams are not wired (the `AudioBus` plumbing is ready — drop `.ogg`/`.wav` into `assets/audio/` and assign to the WeaponData `.tres` files).
- The android's "cover" behavior is a flank-position heuristic, not true cover-point search. Good enough for now; full cover scoring is a follow-up.
