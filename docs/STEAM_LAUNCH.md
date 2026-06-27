# Launching AI Uprising on Steam

This is the end-to-end guide. It's split into **what's already automated in this
repo** and **what only you can do** (anything needing a Steam account, money, or
manual review — those can't be scripted).

---

## TL;DR

1. Build the binaries:  `pwsh tools/build_release.ps1`  → `build/windows/ai-uprising.exe`, `build/linux/ai-uprising.x86_64`
2. Pay the one-time **$100 Steam Direct** fee and create the app in Steamworks → get your **App ID**.
3. Fill the **store page** (description, capsule art, screenshots, trailer, price).
4. Create **Windows + Linux depots**, set the **launch options**.
5. Fill in the IDs in `tools/steam/app_build.vdf` and upload with `steamcmd`.
6. Set the build **live**, complete the **content/age-rating survey**, request **review**, pick a **release date**, hit **Release**.

---

## Part A — Already done / automated (in this repo)

- **Release version** set: `application/config/version = "1.0.0"` in `project.godot`.
- **Export presets** committed (`export_presets.cfg`): `Windows Desktop` and `Linux`,
  both single-file (PCK embedded), `tests/*` excluded.
- **Build script**: `tools/build_release.ps1`
  - `pwsh tools/build_release.ps1` — exports both targets.
  - `pwsh tools/build_release.ps1 -InstallTemplates` — first run on a clean
    machine: downloads + installs the matching **4.7 export templates** automatically.
  - `-Godot <path>` if your Godot binary isn't the default Downloads location.
- **Builds verified**: both export and the Windows build boots clean (Godot 4.7,
  Vulkan, main menu). Output goes to `build/` (gitignored — don't commit 300 MB exes).
- **Steam upload config**: `tools/steam/app_build.vdf` (SteamPipe content-build
  script). You only fill in three IDs and run `steamcmd` (Part E).

Everything past this point needs your Steamworks partner account, so it's manual.

---

## Part B — Steamworks account + create the app  (manual; ~$100)

1. Create a partner account at <https://partner.steamgames.com> (company/tax/bank
   info required for payouts).
2. Pay the **Steam Direct fee** ($100 USD per app; recoupable after $1,000 in sales).
3. **Create New App** → you get an **App ID** (e.g. `1234567`). Write it down.
4. In **App Admin** you'll work through the checklist Valve generates. The big
   items are below.

---

## Part C — Store page  (manual; this is the marketing surface)

App Admin → **Store Presence → Store Page**. You need:

- **Name / short & full description** — pull copy from the game itself: it's a
  fast arena FPS where humanity fights a rogue-AI uprising across 18 levels, with
  parody "AI faction" levels (GPT/Gemini/Claude/Grok), per-level comic briefings,
  ~25 enemy types, bosses, an arsenal of 17 weapons, dash/slide/melee, and an
  enemy codex. Three difficulties.
- **Tags**: FPS, Action, Sci-fi, Singleplayer, Robots, Fast-Paced, Difficult.
- **Capsule / header art** (you must make these images — sizes Valve requires):
  - Header capsule **460×215**
  - Small capsule **231×87**
  - Main capsule **616×353**
  - Vertical capsule **374×448**
  - Page background **1438×810**, plus a **community icon 184×184** and **library
    assets** (capsule 600×900, header 460×215, hero 3840×1240, logo).
  - You already have per-level comic art in `assets/comics/` and the box-art
    style poster — good source material to crop/compose capsules from.
- **Screenshots**: at least 5 (1920×1080). Capture in-game with PrintScreen, or
  reuse the framing probes in `tests/` (e.g. `level_shot`).
- **Trailer**: strongly recommended. Record gameplay (OBS) → upload an MP4.
- **Pricing**: set your price in App Admin → pick a tier; Steam fills regional prices.

---

## Part D — Application / build settings  (manual)

App Admin → **SteamPipe → Depots** and **Installation → General**:

1. **Depots** — create two (Steam usually pre-creates `AppID+1`):
   - a **Windows** depot (note its Depot ID)
   - a **Linux** depot (note its Depot ID)
2. **Launch options** (Installation → General → "Launch Options"):
   - Windows: executable `ai-uprising.exe`, OS = Windows.
   - Linux: executable `ai-uprising.x86_64`, OS = Linux (mark it executable; the
     export already sets the bit).
3. **Supported OSes / system requirements**: Windows 10+ and a Vulkan-capable GPU
   (the game uses Forward+/Vulkan). Min ~4 GB RAM, ~1 GB disk.

---

## Part E — Build & upload  (mostly automated)

1. Build: `pwsh tools/build_release.ps1`
2. Install **SteamCMD** (<https://developer.valvesoftware.com/wiki/SteamCMD>) and
   sign in once interactively as your builder account (so Steam Guard is cached).
3. Edit **`tools/steam/app_build.vdf`** and replace `YOUR_APP_ID`,
   `WINDOWS_DEPOT_ID`, `LINUX_DEPOT_ID` with your real IDs. Bump the `Desc` per build.
4. Upload:
   ```
   steamcmd +login <builder_account> +run_app_build <abs-path-to>\tools\steam\app_build.vdf +quit
   ```
   This pushes both depots. Watch for "Success" / a BuildID.
5. In Steamworks → **SteamPipe → Builds**, **Set Build Live** on the `default`
   branch (test on a `beta` branch first if you like).

---

## Part F — Release requirements  (manual; Valve-gated)

- **Content survey / age rating** (App Admin → "Edit Store Page → Content survey"):
  declare violence (robot/sci-fi combat, no gore-by-default), no sexual content,
  etc. This drives the store rating.
- **Store page review**: submit the page; Valve reviews it (usually a few business days).
- **Build review**: your first build is reviewed before you can launch.
- **Release date**: set it (must be ≥ a couple weeks out so the "Coming Soon" page
  can bank wishlists). On the day, hit **Release**.

---

## Part G — Optional: native Steam features (achievements, cloud, overlay)

The game ships fine without these — but if you want the Steam **overlay**,
**achievements**, **rich presence**, or **Steam Cloud** saves, integrate the
Steam SDK via **GodotSteam** (the SDK isn't bundled here because it's a
platform-specific GDExtension binary that has to match your Godot build):

1. Get **GodotSteam GDExtension** for Godot 4.7 (<https://godotsteam.com>), drop
   `addons/godotsteam/` into the project.
2. Put a `steam_appid.txt` (your App ID) next to the editor + the exported exe for
   local testing (do **not** ship it in the public depot).
3. `Steam.steamInit()` on boot; map achievements to existing signals — e.g.
   `GameState.level_completed` / `level_graded` (per-level + S-rank achievements),
   `enemy_killed`, boss-kill signals. Cloud-sync the existing `user://*.cfg`
   saves (`savegame.cfg`, `records.cfg`, `bestiary.cfg`).
4. Re-run `tools/build_release.ps1`; the addon ships inside the PCK.

---

## Pre-launch checklist

- [ ] `pwsh tools/build_release.ps1` succeeds; both binaries boot to the menu.
- [ ] App ID + both Depot IDs filled into `tools/steam/app_build.vdf`.
- [ ] Build uploaded via steamcmd and **set live** on `default`.
- [ ] Launch options set for Windows **and** Linux.
- [ ] Store page: description, all capsule art, ≥5 screenshots, trailer, price.
- [ ] Content/age survey submitted; store page + build approved by Valve.
- [ ] Release date set; wishlist "Coming Soon" page is live.
- [ ] (Optional) GodotSteam achievements/cloud wired and tested.
