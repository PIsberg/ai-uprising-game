---
name: changelog-clip
description: >-
  Film a change before and after: record the same scripted gameplay on two
  commits with Godot Movie Maker and publish a frame-locked viewer page where
  each PR is a marker that jumps to the moment it shows. Use when the user wants
  an interactive changelog, a recording, video or before/after of a change or
  a PR chain.
---

# Changelog clip

Each clip is a **pair**: `tools/changelog_clip.tscn` filmed on a *before* commit and an *after*
commit with identical args. Movie Maker's fixed step (`--fixed-fps 60`) gives every frame exactly
1/60 s of game time, so frame N of one matches frame N of the other and any difference is the
change. The viewer (`viewer.html` beside this file) plays pairs side by side, as a wipe or as a
flip, and turns each PR into a timeline **marker**.

Work in `build/changelog/<slug>/` (gitignored). Needs a window, ffmpeg, and `GODOT_BIN` set to the
4.7 console binary. Run the scripts from Git Bash.

## Steps

1. **Pin the commits and the PRs.** *after* is the merge that landed the last PR (or a branch
   head); *before* is the first parent of the merge that landed the first one
   (`git rev-parse --short <merge>^1`). For each PR, `gh pr view <n> --json title,body`. Done when
   you hold two SHAs and, per PR, a title plus a one-to-two sentence *why* in player terms, with
   numbers from the PR body.

2. **Plan the shots.** The clip scene parks a target robot 9 m down the Armory range lane with its
   AI off, aims at it, fires a burst and reloads. Args: `gun=<scenes/weapons id>`,
   `enemy=<LevelBuilder.ENEMY_SCENES id | none>` (`none` fires into a plain wall slab instead,
   for impact changes), `burst=<seconds>`. Pick the gun and robot that make each PR's change largest
   on screen (a matchup PR wants a robot the gun counters). Done when every PR maps to a clip that
   shows it, or carries an `absent` reason the viewer prints instead. A change the scene cannot
   show (a menu, a level, a robot's AI) needs a new mode in `tools/changelog_clip.gd` and a check
   in `tests/changelog_clip_probe.gd` first.

3. **Record each pair.**
   ```sh
   tools/changelog_record.sh <before> build/changelog/<slug>/clips/before_<id>.mp4 gun=shotgun enemy=drone
   tools/changelog_record.sh <after>  build/changelog/<slug>/clips/after_<id>.mp4  gun=shotgun enemy=drone
   ```
   The first run per commit creates `../.wt-changelog-<sha>` and imports it (a few minutes); each
   recording then takes about 2 minutes and comes out around 2 MB. Done when both runs print `ok`
   with the **same `frames=`**. A SCRIPT ERROR on the older commit means the clip uses an API it
   lacks: move *before* later or film that PR in a later pair.

4. **Place the markers by eye.** `tools/changelog_strip.sh before.mp4 after.mp4 strip.png` writes
   one row per 0.25 s (row i = i × 0.25 s), before left and after right. Read the PNG. A marker is
   the first row where the PR's change is visible in *after* against *before*. Pull a full frame
   to confirm a small detail:
   `ffmpeg -ss <t> -i after.mp4 -frames:v 1 f.png`. Done when every marker was seen in a frame,
   none inferred from PR text, and anything odd you noticed is noted for the user (the clip
   is a playtest too).

5. **Build the page.** Copy `viewer.html` to `build/changelog/<slug>/index.html`, set its
   `<title>` to the changelog's name, and write `changelog.json` beside it (schema below). Done
   when every clip's `frames` matches the recorder's output and every `marks` key is a PR in
   `prs`.

6. **Publish and link.** Publish with the Artifact tool: `file_path` the `index.html`, `files`
   mapping `changelog.json` and every `clips/*.mp4` to themselves (`root` the slug folder). The
   tool reads only under the session's working directory or scratchpad: working in another
   worktree, copy the slug folder to the scratchpad first. To update an earlier page keep its URL
   by passing `url`. Then add the link to `CHANGELOG.md` on the
   entries it films. The page is private until the user shares it; say so. Done when the link is
   in the changelog and in your reply.

7. **Clean up.** `git worktree remove ../.wt-changelog-<sha>` for each commit you will not film
   again.

## changelog.json

```json
{
  "title": "Weapon feel, before and after",
  "eyebrow": "AI Uprising · patch notes you can play",
  "lede": "One paragraph: what was filmed and how to use the page.",
  "before": "9f7e317", "after": "2e763de",
  "repo": "PIsberg/ai-uprising-game",
  "method": "Footer: the clip args, the fixed step, what can differ between runs.",
  "prs": [ { "n": 353, "title": "…", "why": "…", "absent": "heavy guns only" } ],
  "clips": [ { "id": "shotgun", "label": "SG-12 Breacher", "note": "Shotgun into a parked drone",
               "before": "clips/before_shotgun.mp4", "after": "clips/after_shotgun.mp4",
               "frames": 381, "marks": { "353": 0.5, "351": 0.75 } } ]
}
```

`marks` maps a PR number to seconds into the clip. A PR missing from one clip's `marks` points the
viewer at another clip that has it, else prints its `absent`. Gun display names are
`display_name` in `assets/weapons/<id>_data.tres`.

## Traps

- **Live input swings the camera.** A stray OS mouse event reaches `player.gd` mouse-look; the
  clip turns input off on the player and the WeaponManager, and `changelog_clip_probe` pins it.
  Keep that in any new mode.
- **Leave the window alone while it records.** Resizing it streaks the readback, and
  `--resolution` is ignored (the project's 1920x1080 wins); the recorder scales to 1280.
- **RNG still runs.** Damage numbers, pellet scatter and sparks use the game's RNG, so they can
  differ slightly between the two runs. Say so in `method`.
- **The AVI is huge.** Quality 1.0 MJPEG is about 590 MB for 7 s; the recorder deletes it after
  encoding.
