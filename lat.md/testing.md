# Verification and Testing Strategy

We follow a rigorous automated verification philosophy. Every feature added to the codebase should have a corresponding test scene called a "probe."

## Verification Philosophy
<!-- lat: { "require-code-mention": true } -->
All changes should be proved headlessly. Every logic test ships with a matching pair:
1. A logic probe script (`.gd`).
2. A matching probe scene (`.tscn`).
Probes run in Godot's headless mode and print either `RESULT PASS` or `RESULT FAIL`.

## Test Probes Guidelines
To ensure test probes run correctly and do not freeze:
* **Spawn Floors:** Always instantiate a floor node (`StaticBody3D`, collision layer 1). Character Body movement asserts will fail if entities fall indefinitely.
* **Avoid Long Timers:** Use short loops (0.25s - 0.3s) to poll for condition checks. Long `SceneTreeTimer` delays stall autoload updates under headless execution.
* **Execution Watchers:** Scene tree modifications can delete the active scene. Run watch/cleanup functions from node watchers parented directly under root.

## Execution CLI
Command-line tools to execute single probes or the entire test suite.

* Run the full headless test runner suite:
  ```sh
  tools/run_tests.sh
  # On Windows:
  tools/run_tests.ps1
  ```
* Run a single logic test:
  ```sh
  godot --headless --path . --audio-driver Dummy res://tests/<test_name>_probe.tscn
  ```

## Integrity and Lattice Verification
Ensures suite manifests stay synchronized and architectural references remain intact.

* Verify probe manifest consistency against `tests/README.md`:
  ```sh
  python tools/check_suite_manifest.py
  ```
* Verify every localization row parses into one column per language (an unquoted comma in `assets/i18n/strings.csv` silently re-keys or shifts a row), and that every task, wave and firewall label in the level defs, and every builder default label, has a row:
  ```sh
  python tools/check_strings_csv.py
  ```
* Verify no texture extracted from a GLB is left beside a model that embeds its own images (the export ships every such file unused; 207 of them were 179 MB of the pack). Any image named `<model>_*` beside `<model>.glb` counts, unless a text resource names it or a glTF model loads it by URI:
  ```sh
  python tools/check_glb_leftovers.py
  ```
* Verify no tracked file is over its size budget: 50 MB for any file (GitHub's warning threshold) and 3 MB for a still under `docs/`. The capture tools save at window size (3840x2400, 5 to 13 MB a PNG); `python tools/shrink_screenshots.py` takes a README still down to 1600 px wide. Frame dumps and verification shots from the capture tools (`docs/screenshots/<tool>/`) are gitignored:
  ```sh
  python tools/check_large_files.py
  ```
* Verify the imported assets a release ships stay inside their size budget (the pack is almost all `.godot/imported`, so this tracks build size without exporting). Needs a populated `.godot`; the budgets in the script are a ratchet, lowered when an asset pass lands. It also fails on any shipped texture over 1 MB imported lossless: 2D art goes lossy, a texture on a mesh VRAM-compressed with mipmaps (a headless import never runs the editor's detect-3D step, so extracted model textures stay lossless until set):
  ```sh
  python tools/check_import_budget.py
  ```
* Validate Agent Lattice documentation links and code references:
  ```sh
  lat check
  # Or via npm script:
  npm run lat:check
  ```
