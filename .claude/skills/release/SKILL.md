---
name: release
description: >-
  Build and publish/update the AI Uprising game to a release target (currently
  itch.io — gotrex/ai-uprising). Use when the user wants to release, publish,
  ship, deploy, or push an update of the game — e.g. "/release itch", "release
  the game", "ship an update to itch", "publish the new build".
---

# Release AI Uprising

Publishes the game to a distribution target by running the project's release script,
which rebuilds fresh Windows + Linux binaries and pushes them to itch.io with `butler`
(delta-patched, so updates only upload what changed).

## How to run

1. Read the target from the user's args. Default and only supported target today is `itch`.
2. Run the release engine and stream its output live:

   ```powershell
   pwsh -NoProfile -File tools/release.ps1 <target>
   ```

   (Equivalently, the user can type `./release <target>` in a terminal — `release.cmd`
   and the `release` bash shim both delegate here.)

   - Add `-SkipBuild` when the user only wants to re-push the current `build/` artifacts
     without the ~10-minute rebuild (e.g. they already built, or only page metadata changed).

3. What the script does, in order:
   - Verifies `butler` is installed and **logged in**. If not logged in it stops and prints
     the one-time `butler login` command. **Relay that command to the user and stop** — they
     must run it themselves; it opens a browser to authorize. Never attempt to log in for them
     or handle their credentials.
   - Rebuilds the release binaries via `tools/build_release.ps1` (unless `-SkipBuild`).
   - `butler push`es both channels (`:windows`, `:linux`) with a version stamp derived from
     the date + git short SHA.

4. On success, report the live URL — https://gotrex.itch.io/ai-uprising — and the version
   stamp the script printed. For an already-public page the update is **live immediately**;
   there is no manual "publish" click.

## Notes & gotchas

- **First run only:** `butler login` must be done once. The itch game page must already exist
  (it does: gotrex/ai-uprising).
- **Duplicate downloads:** the original launch uploaded zips through the itch web uploader.
  `butler` uploads to named channels, which are *separate* from those web uploads. After the
  first `butler push`, suggest the user delete the old manually-uploaded zips on the itch
  dashboard so players don't see duplicate download buttons.
- **Build size:** each binary is ~600 MB; a full rebuild + push takes a while. Prefer
  `-SkipBuild` for a quick re-push when nothing in the game changed.
- Adding another target later (e.g. Steam) is a new `case` in `tools/release.ps1` and a line here.
