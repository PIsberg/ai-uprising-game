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
* Verify every localization row parses into one column per language (an unquoted comma in `assets/i18n/strings.csv` silently re-keys or shifts a row):
  ```sh
  python tools/check_strings_csv.py
  ```
* Validate Agent Lattice documentation links and code references:
  ```sh
  lat check
  # Or via npm script:
  npm run lat:check
  ```
