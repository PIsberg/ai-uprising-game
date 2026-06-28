# Releasing **AI Uprising** to itch.io

A step-by-step guide to build, package, and publish the game on
[itch.io](https://itch.io). Written for the current project (Godot 4.7,
`config/version = 1.0.0`, **Forward+** renderer).

> TL;DR
> 1. Do the **Pre-release checklist** (especially **asset licensing**).
> 2. Install Godot **export templates** + **butler**.
> 3. Run `tools/package_release.ps1` → produces `dist/*.zip`.
> 4. Create the itch project page, then `butler push` each zip.

---

## 0. What you're shipping

Recommended for v1.0: **downloadable desktop builds** — Windows + Linux. These
keep the game's Forward+ look and run well for a 3D FPS.

| Platform | Preset (already configured) | Output |
|---|---|---|
| Windows | `Windows Desktop` | `build/windows/ai-uprising.exe` (self-contained) |
| Linux | `Linux` | `build/linux/ai-uprising.x86_64` (self-contained) |
| macOS | *not set up* — optional, see §6 | `.app` / `.zip` |
| Web (HTML5) | *not set up* — **not recommended**, see §5 | `index.html` + data |

Both desktop presets already **embed the PCK** (one self-contained file) and
**exclude `tests/*`**, so the packaged build is clean.

---

## 1. Pre-release checklist

- [ ] **Asset licensing (do this first — it's the one that can get a page taken down).**
      The imported enemy models (`assets/models/robots/*.glb` you added — combat_robot,
      mech_police, steampunk, reaper_whirlwind, robot_shark, robot_dog, etc.) must be
      **cleared for redistribution**. For each: confirm the license allows redistribution
      in a game, and list it in `CREDITS.md` with author + source + license. If any is
      "personal use only" or unclear, **remove it or replace it** before publishing.
      (The CC0 Quaternius/Kenney assets already in the repo are fine.)
- [ ] **Music/audio** — same check. Procedural SFX you generate is fine; any recorded
      samples under `assets/audio/samples/` need a redistributable license.
- [ ] `config/version` in `project.godot` matches the version you're publishing (currently `1.0.0`).
- [ ] Run the test suite — `pwsh tools/run_tests.ps1` — all probes green.
- [ ] Play a full level from a packaged build (not the editor) — see §4.5.
- [ ] **Quit works**: confirm there's an in-game way to exit (Esc → menu → Quit), since
      the game launches fullscreen (`window/size/mode = 3`).
- [ ] Decide **price** (free / "name your price" / paid) and **cover art** (see §7).
- [ ] `CREDITS.md` is complete and shown/linked in-game or on the page.

---

## 2. Prerequisites (one-time)

1. **Godot 4.7** (you have it). Note the console binary path; the scripts use
   `GODOT_BIN`:
   ```powershell
   $env:GODOT_BIN = "C:\Program Files (x86)\godotengine4.7\Godot_v4.7-stable_win64_console.exe"
   ```
2. **Export templates** for 4.7 — required to export. In the Godot editor:
   *Editor → Manage Export Templates → Download and Install*.
   (They're likely already installed since `build/` exists.)
3. **An itch.io account** → https://itch.io/register
4. **butler** (itch's upload CLI — strongly recommended for fast, resumable,
   patch-based uploads):
   - Download: https://itchio.itch.io/butler (or `https://broth.itch.io/butler`)
   - Put `butler.exe` on your `PATH`, then:
     ```powershell
     butler login        # opens a browser to authorize once
     butler version       # confirm it works
     ```

---

## 3. Build & package (the easy path)

From the project root:

```powershell
$env:GODOT_BIN = "C:\Program Files (x86)\godotengine4.7\Godot_v4.7-stable_win64_console.exe"
pwsh tools/package_release.ps1                # runs tests, exports, zips
# or skip the test gate:
pwsh tools/package_release.ps1 -SkipTests
```

This produces:
```
dist/ai-uprising-windows-1.0.0.zip
dist/ai-uprising-linux-1.0.0.zip
```

(Linux/macOS host: `GODOT_BIN=/path/to/godot ./tools/package_release.sh 1.0.0`.)

### 3.5 Manual export (alternative, via the editor)
*Project → Export…* → select **Windows Desktop** → *Export Project* (uncheck
"Export With Debug") → save to `build/windows/ai-uprising.exe`. Repeat for
**Linux**. Then zip each file.

---

## 4. Test the packaged build

Always smoke-test the **exported** build, not the editor — exports can differ:

1. Run `build/windows/ai-uprising.exe` directly.
2. Check: main menu loads, a level deploys, combat works, audio plays, pause/quit work.
3. If you see missing textures/effects, re-check the export `exclude_filter`
   (should only be `tests/*`).

---

## 5. Web (HTML5) — optional, **not recommended for v1**

itch loves browser-playable games, **but this project uses the Forward+
renderer**, and Godot's Web export only supports the **Compatibility** renderer.
Switching has real costs here:

- Volumetric fog (`env.volumetric_density` in several levels) and some glow/SSAO
  won't render the same or at all.
- Browser performance for a 3D FPS is marginal; load times are large.

If you still want a web build later:
1. *Project Settings → Rendering → Renderer → Rendering Method* → add a
   **Compatibility** fallback (or switch the project) and re-test everything.
2. Add a **Web** export preset, export to a folder, **zip the folder** (must
   contain `index.html`).
3. On the itch upload, tick **"This file will be played in the browser"** and set
   the embed viewport (e.g. 1280×720), with "Fullscreen button" + "Mobile
   friendly" off.

Recommendation: ship desktop now; treat web as a separate later task.

---

## 6. macOS — optional

No preset is set up. macOS builds exported from Windows are **unsigned**, so users
get a Gatekeeper warning (right-click → Open) unless you have an Apple Developer
ID to sign/notarize. If you want it:
1. In the editor, *Project → Export… → Add… → macOS*, export a `.zip`.
2. Upload it and tick the **macOS** platform on the file.

---

## 7. Create the itch.io project page

1. Go to **https://itch.io/game/new** (or Dashboard → *Create new project*).
2. **Title:** `AI Uprising` · **Project URL:** `ai-uprising` (note the
   `YOURNAME/ai-uprising` slug — you'll need it for butler).
3. **Classification:** *Games*.
4. **Kind of project:** *Downloadable* (choose *HTML* only if you did §5).
5. **Pricing:** Free / *No payments* or *Name your own price* (recommended for a
   first release) or a fixed price.
6. **Uploads:** you can drag the zips here for a manual first upload, **or** leave
   empty and use butler (§8 — recommended).
7. For each uploaded file, tick the correct **platform(s)** (Windows / Linux /
   macOS) so itch shows the right download buttons and the itch app installs them.
8. **Cover image:** 630×500 px (shown in listings) — required to be listed.
9. **Screenshots / GIFs:** add 3–5 (the README gallery is a good source).
10. **Genre/Tags:** e.g. `FPS`, `Shooter`, `Sci-fi`, `Singleplayer`, `3D`,
    `Action`, `Godot`. **Description:** paste a trimmed version of `README.md`.
11. **Community/Comments**, **Visibility** — leave as *Draft* until you've tested,
    then set **Public**.
12. Save & *View page* → test the download.

---

## 8. Upload builds with butler (recommended)

butler uploads to **channels** (one per platform) and only sends changed bytes on
updates. Replace `YOURNAME` with your itch username.

```powershell
butler push dist/ai-uprising-windows-1.0.0.zip YOURNAME/ai-uprising:windows --userversion 1.0.0
butler push dist/ai-uprising-linux-1.0.0.zip   YOURNAME/ai-uprising:linux   --userversion 1.0.0
```

- The **channel name** (`windows`, `linux`) makes itch auto-tag the platform.
- `--userversion` sets the version shown on the page (use your `config/version`).
- Check status: `butler status YOURNAME/ai-uprising`.

itch processes the upload; refresh your dashboard and the files appear under the
project. Set the page **Public** when ready.

---

## 9. Shipping updates later

1. Bump `config/version` in `project.godot` (e.g. `1.0.1`).
2. Re-run `pwsh tools/package_release.ps1`.
3. `butler push dist/ai-uprising-windows-1.0.1.zip YOURNAME/ai-uprising:windows --userversion 1.0.1`
   (same channel → users on the itch app get an auto-update).

---

## 10. Quick reference

```powershell
# one-time
$env:GODOT_BIN = "C:\Program Files (x86)\godotengine4.7\Godot_v4.7-stable_win64_console.exe"
butler login

# every release
pwsh tools/package_release.ps1
butler push dist/ai-uprising-windows-1.0.0.zip YOURNAME/ai-uprising:windows --userversion 1.0.0
butler push dist/ai-uprising-linux-1.0.0.zip   YOURNAME/ai-uprising:linux   --userversion 1.0.0
```

## Notes for the repo
- `build/` and `dist/` are build artifacts — add them to `.gitignore` so large
  binaries don't get committed.
- The `Windows Editor` export preset bundles the level editor; it's for you, not
  for players — don't upload it as the main download.
