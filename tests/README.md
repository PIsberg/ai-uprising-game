# tests/ — probe index

Probes are the verification mechanism for this repo (see root `CLAUDE.md` →
*Verification philosophy*). Nearly every feature ships with a probe (a `.gd` +
`.tscn` pair) that exercises the real systems and prints `RESULT PASS` /
`RESULT FAIL`. Logic probes run fully headless (no GPU); screenshot probes
need a real window and render black under `--headless`.

## Running probes

Single probe (headless, if the probe supports it):

```sh
godot --headless --path . --audio-driver Dummy res://tests/<name>.tscn
```

Single probe (windowed — required for anything that screenshots or judges a
render):

```sh
godot --path . res://tests/<name>.tscn
```

Full headless suite (imports the project, then runs every probe in
`tools/run_tests.sh`'s `PROBES` array and checks each printed `RESULT PASS`):

```sh
tools/run_tests.sh          # bash / CI
tools/run_tests.ps1         # Windows
```

`GODOT_BIN` overrides the binary (defaults to `godot` on PATH). A handful of
probes take extra CLI args after `--` (e.g. `model_view_probe`,
`boss_ingame_probe`, `lava_probe`) — check the probe's own header comment.

## Probe index

244 probes total: **30** wired into the headless suite (`suite`), **83**
headless-capable but not wired in (`headless` — some print the `RESULT
PASS`/`FAIL` convention and are strong candidates to add; others are
report-only diagnostics/telemetry tools with their own print format and are
intentionally not suite-shaped), **135** windowed-only (`windowed` — screenshot
or GPU-timing probes; `--headless` renders these black).

| Probe | Verifies | Mode |
|---|---|---|
| aaa_axes_probe | Batch-3 five-axis AAA gaps on a live level: warp-in telegraph before spawn, lava heat-haze curtains, per-level par time + speed bonus, wounded-grunt cover-seek fallback | headless |
| adrenaline_probe | ADRENALINE SURGE: critical-HP hit fires heal+buff+banner, buffs collapse on end, cooldown blocks immediate re-trigger | windowed |
| ads_zoom_probe | Holding aim (RMB) converges FOV to the weapon's ads_fov; release restores base FOV | headless |
| ai_director_probe | Adaptive AI Director's counter logic against synthetic playstyle profiles | suite |
| aim_hit_probe | Aiming at a robot actually damages it: every weapon vs a reference enemy at 6/18/35m (skipping ranges past each weapon's own `range_m`), and every one of the 43 enemies vs the rifle (~319s, run deliberately) | headless |
| alien_probe | ALIEN charges, spits bio-plasma orbs, orbs damage the player without melee | headless |
| archon_probe | ARCHON boss full lifecycle (boot→wave spawn→exposure→energy fire→death cascade) headlessly for script errors | headless |
| armed_lineup_probe | Blender-armed bot forks lined up to eyeball welded weapons | windowed |
| armory_probe | GRENADE POWER + LIFELEECH armory tracks; renders the Armory UI (5-upgrade + 3-supply layout) | windowed |
| armory_shot | Armory shop rendered with partial/empty/maxed upgrade states | windowed |
| b3_bowler_throw | STRIKER-9 throws a live MOLTEN ORB that flies/lands/hunts; 3-orb cap | headless |
| b3_manus_parts | Dumps every MANUS MeshInstance3D with world AABB to locate hand vs base ends | headless |
| b3_manus_yaw | Four MANUS instances at yaw 0/90/180/270 to pick the orientation facing camera | windowed |
| balance_probe | Combined move-speed buff stack is capped while damage/fire-rate spikes report uncapped | headless |
| batch3_enemy_probe | The 5 batch-3 enemies staged + screenshotted; MANUS weak-spot gating + orb thrown-mode flight | windowed |
| batch3_probe | The 4 batch-3 models inspected with screenshots + structure dump | windowed |
| beam_axial_probe | ElectricBeam at exact in-game endpoints; bright-pixel count confirms it renders along the aim axis | windowed |
| beam_render_probe | ElectricBeam renders to a PNG (lightning actually draws) | windowed |
| benchmark_probe | QualityBenchmark run twice; measured avg ms (needs real GPU timings) | windowed |
| bevel_smoke | BeveledBoxMesh instances from both a `.tscn` sub_resource and code, non-empty geometry | headless |
| blast_direction_probe | A BRUTE's frontal shield judges an explosion by the BLAST's position, not the thrower's — a grenade behind it lands, one in front is blocked | suite |
| blur_shot | Clean high-res indoor capture (forced HIGH + full render scale) to diagnose "indoor looks blurry" | windowed |
| bolt_bare_probe | Bare-scene isolation of the bolt material on distant columns; transparent-surface culling | windowed |
| bomb_audio_probe | Mega-bomb detonation into a dense cluster; audio bus state before/after (silence-after-bomb regression) | headless |
| boot_capture | Helper parented to `/root`; screenshots the boot flow across `change_scene` (loaded by boot_probe) | windowed |
| boot_probe | App boot into the loading screen → title → main menu | windowed |
| boss_entrance_all | Every boss entrance staged on a dark arena; timed frame sequences to judge uniqueness/impact | windowed |
| boss_entrance_probe | GOLIATH-IX sky-drop and OVERSEER portal entrances; timed frames | windowed |
| boss_ingame_probe | Real boss scene, entrance cancelled, screenshots idle + walking; lists animation clips | windowed |
| boss_move_probe | COLOSSUS seismic footfall crush/fling and TERMINATOR circle-strafe (lateral velocity) signatures | headless |
| boss_signature_probe | SMASHER claw-rake lunge and OVERSEER rocket-barrage signature attacks land | windowed |
| bounty_probe | BOUNTY director: tagged-enemy kill awards bonus + clears director + always drops the rare prize | windowed |
| briefing_probe | Real finale (archon) level_briefing: preview mode shows the boss with no minion waves/portal | windowed |
| briefing_view | Per-level comic briefings: art + glow FX + weather + title/tagline/objective all show | windowed |
| brute_shield_probe | BRUTE still visibly carries its frontal shield slab (front + 3/4 shots) | windowed |
| campaign_dump | SceneTree script dumping `max_level_reached` + full campaign roster for inspection | headless |
| campaign_map_probe | Campaign map at a mid-run progress state, screenshotted | windowed |
| campaign_nav_sweep | Full-campaign softlock guard: every LevelDefs level's exit is navmesh-reachable from spawn | headless |
| campaign_smoke | Full-campaign live smoke test: boots every level scene, bakes navmesh, reports build/player/health per level | headless |
| chapters_test | Campaign chapter groupings end on the expected level titles | headless |
| checkpoint_probe | Mid-level checkpoint/respawn: task completion sets a checkpoint; dying after relocating restores it | headless |
| claude_showcase | Claude vault showcase; framed views of the centrepiece/lighting | windowed |
| cluster_probe | OMEGA/NOVA cluster-carpet grenades detonate their staggered bomblets | headless |
| codex_audit_probe | Encyclopedia stage audit: boss FX + a switch test (boss→drone) for FX sticking to the next entry | windowed |
| codex_check_probe | Specific codex entries (drone/raptor/gunner/overseer) render once discovered | windowed |
| codex_count_probe | Warp cheat's `discover_all_enemies()` count of enemies the Codex would show | suite |
| codex_frame_probe | Blender-edited/re-exported models still frame correctly in the codex viewer's bone-AABB framing | windowed |
| codex_probe | Comic intro's three panels + a few Encyclopedia entries captured | windowed |
| codex_sheet_probe | Contact-sheet grids of every codex entry, for eyeballing stray FX / misoriented models | windowed |
| color_grade_probe | Every GraphicsSettings.ColorGrade preset cycled on level_01 and screenshotted | windowed |
| comic_page_probe | Assembled three-panel comic intro page after all panels slide into place | windowed |
| content_probe | Late-game content: TEMPEST chain lightning, VORTEX grenade pull-in+detonate, hoppier SKITTER | headless |
| convoy_playtest | Playtest bot rides Highway Breakout end to end (stays aboard, aim-assists, fires, exits) — is it winnable | headless |
| convoy_probe | Highway Breakout ride end to end: hauler rolls, player rides the deck, pursuit waves spawn, brute boards, friendly fire blocked, zipline out/back, and the demo charge reaches every Damageable inside its radius (kills are telemetry, not asserted — they depend on which wave is alive) | suite |
| convoy_shot | Highway Breakout ride mid-roll: truck deck + roadside dressing | windowed |
| crosshair_probe | Weapons with different spread identities; crosshair reads real per-weapon spread/aim data | windowed |
| damage_dir_probe | Damage-direction arc renders screen-right of the crosshair for a hit from the player's right | windowed |
| damage_number_size_probe | Accessibility Damage Number Size (GraphicsSettings.damage_number_scale 0.6..2.0): a real player-dealt hit spawns a Label3D whose fixed-size pixel_size is 0.0028 x the slider (1.0 / 2.0 / 0.6 measured), setter clamps, value persists; restores the user's values | suite |
| dark_spot_probe | Mean frame luminance from spawn, per campaign level, ranking under-lit "dark spot" levels | windowed |
| damage_source_probe | `Damageable.apply_damage` survives a FREED or non-Node `source` (shooter died before its projectile landed) and still applies the damage | suite |
| dash_probe | Dash i-frame phase-through: soft enemy separation stands in for hard collision during the dash window | headless |
| death_probe | Player death: fall-over + input lockout + game-over flow | windowed |
| debrief_shot | Victory screen's mission-debrief line (KILLS/DEATHS) matches known source stats | windowed |
| difficulty_curve | Per-level THREAT INDEX (enemy DPS+survivability) shows the campaign ramps up; EASY/NORMAL/HARD spread modelled | headless |
| difficulty_scaling_check | How many spawners survive `apply_level_scaling` per difficulty on a representative level | headless |
| directive_probe | Per-level COMBAT DIRECTIVE mutators: mult getters, damage-hook effects, roll chance, HUD announcement | windowed |
| dismember_probe | Android damaged past health thresholds; panels shed mid-degradation without errors | windowed |
| dodge_probe | PERFECT DODGE: a hit negated by dash i-frames scores a bonus+banner once per dash; non-dashing hit does not | windowed |
| elite_probe | `Elite.maybe_apply` pre-`add_child` with a forced roll (catches the "get_node from outside tree" regression) | suite |
| ember_probe | Lava beds build ember emitters with a visibility_aabb large enough to survive frustum culling; water beds don't spark | headless |
| emp_probe | `emp_disable()` timer/inertness and the EMP grenade's fuse-triggered radius disable | suite |
| enemy_behavior_probe | Optic (cutting beam) and Roller (ground ram) signature behaviour against a stationary dummy | windowed |
| enemy_combat_probe | Every new enemy engages (>=CHASE), damages the player, dies cleanly | suite |
| enemy_eval_probe | Objective 1v1 balance eval per enemy: real DPS, closing distance, lateral strafe spread | headless |
| enemy_lineup_probe | Each humanoid model playing its Idle clip front-on, catching models stuck in a Y-pose | windowed |
| enemy_preview_probe | New/changed enemy scenes (AI frozen) post RobotModel auto-fit, for tuning scale/orientation/offsets | windowed |
| enemy_proj_hit_probe | Real player + raptor forced to attack immediately; watches for the enemy-projectile-hit signal type error | headless |
| enemy_react_probe | Grenade-scramble AI (aware android flees a live grenade) + kill-rouses-allies damage-alert cascade | headless |
| enemy_scale_probe | Every enemy's in-game visual height (post RobotModel fit), flagging under-scaled chassis | headless |
| enemy_view_probe | MAGMA WRAITH + ANGLER UNIT side by side under even light, silhouettes/FX | windowed |
| events_probe | Skirmish-event director: ASSASSIN hunter spawn, SUPPLY FLARE cache, GRID SURGE double ultimate-charge rate | headless |
| execute_probe | Melee EXECUTION: shove into low-HP non-boss instakills + fires the reward; healthy enemy just takes shove damage | windowed |
| explosion_screenshot | Both explosion FX types detonated, frame captured mid-expansion | windowed |
| eye_glow_probe | A/B: drone/sentinel eye-glow off vs on under a bloom-lit interior env | windowed |
| feel_audio_probe | AAA feel/audio batch on a live level: synth streams resolve, hazard ambience layers, low-HP heartbeat, sprint lower-ready pose | headless |
| fluid_edge_verify | Peak adjacent-pixel step at a fluid bed's rim, from the fluid_shot captures — proves water/lava blend into the floor instead of stepping. Run AFTER fluid_shot | headless |
| fluid_shot | Isolated top-down rig (one floor, one bed, fixed camera, hazard frame hidden) capturing water + lava rims for fluid_edge_verify; also the only check that water/fluid_margin/lava shaders COMPILE | windowed |
| fierce_probe | Fierce enemy models with real RobotModel tint/material treatment | windowed |
| fix_models_probe | Models whose auto-framing broke, re-rendered with normalized scale/recenter + fixed camera | windowed |
| flyer_pose_probe | Whirlwind/breaker/fishbot flyer trio whose codex entries looked broken | windowed |
| flyer_screenshot | Drone and seeker side by side to compare silhouettes | windowed |
| fx_probe | HUD HP/STA bar captions + the beefed grenade-explosion FX stack mid-blast | windowed |
| fx_render_probe | Energy-bolt flash + impact shock-ring FX upgrade | windowed |
| gate_shot | Gated levels' bulkhead gates/tunnel mouths/guide beacons for clipping/readability | windowed |
| god_cheat_probe | "god" cheat toggles invincibility; a god-mode player survives lethal damage | suite |
| grace_probe | Opening attack grace: enemies close in but land no damage for ~2.5s, then fire resumes | headless |
| graphics_probe | Rain-slick clearcoat ground + explosion scorch decals at ULTRA tier | windowed |
| graphics_shot | Clean first-person ULTRA captures across visually distinct levels — a graphics baseline | windowed |
| grapple_probe | Grapple hook: HUD validity cue, tether attach, winch pull, tether visual lifecycle, release | headless |
| grapple_shot | First-person + third-person shots of the grapple tether mid-pull | windowed |
| grenade_screenshot | Grenade rendered up close, frozen with its core lit | windowed |
| guardrails_playtest | Playtest bot for Generative Guardrails: aims real camera, fires anchor tags, bridges to the override gate | windowed |
| guardrails_probe | Generative Guardrails end-to-end: zone+task registration, hazard pillars, anchor-tag locking, bridging completes the task | windowed |
| gun_range_probe | Live-fires the hitscan arsenal at the range floor; real angular deviation via bullet-hole decals verifies the accuracy model | suite |
| gunner_probe | GUNNER suppresses a player at range; spin-up burst connects, dies cleanly | headless |
| haptics_probe | Gamepad-rumble plumbing without a pad: accessibility scalar mirrors into Haptics, `pulse()` no-ops safely at zero pads/strength | headless |
| hazard_probe | Lava/water hazard arenas: hazard bed exists, flyers spawn, player spawns on a walkway (not the sea) | suite |
| headshot_callout_probe | HUD headshot callout popup via `GameState.report_player_hit(crit=true)` | headless |
| headshot_shot | HEADSHOT callout forced visible to eyeball its style | windowed |
| highlights_probe | Debrief HIGHLIGHTS: engagement systems counted per level with correct singular/plural + streak name | windowed |
| hijack_probe | HIJACK: flips a unit to the player's side, hostiles retarget the traitor, burnout kills + cleans up bookkeeping | headless |
| hints_probe | First-time coaching hints fire exactly once per mechanic, never repeat within a run | headless |
| hitscan_check | Player's hitscan ray flies downrange instead of hitting something right in front of the camera | headless |
| horde_screenshot | Last Stand's first wave, telegraphed, screenshotted | windowed |
| hud_upgrade_probe | HUD upgrade-chip row shows only bought tracks at the right rank | windowed |
| imba_probe | "imba" cheat: every upgrade track maxes + HUD chips rebuild to show all six | windowed |
| indiv_probe | BRUTE shield-in-left-hand idle+punch; VACUUM codex preview rise | windowed |
| intro_screenshot | Intro cutscene's calm phase and post-turn frame | windowed |
| jamming_playtest | Combat playtest bot for Geofenced Signal Jamming: fires + plants beacons to strip hive shields — is it winnable | windowed |
| jamming_probe | Geofenced Signal Jamming: shield absorbs damage, jam zone strips it + disorients, JamZone detection, beacon placement | windowed |
| keybind_probe | Key-rebind persistence: factory defaults, live InputMap application, swap/steal conflict policy, saved overrides | headless |
| kick_stability_probe | Viewmodel-kick spring doesn't diverge to NaN across a frame hitch (shader-compile stall on first shot) | headless |
| killcam_probe | Boss kill-cam time dilation: freeze on boss kill, ease-back to 1.0, sub-boss kills don't trigger it | headless |
| lava_probe | Lava carves the navmesh and leaves a longer connected spawn→exit path; top-down shot | windowed |
| layout_check | Static def check: no prop, pickup, weapon or lore placement sits inside a wall/building AABB. Enemy-spawn and task overlaps are reported as advisory, since the builder relocates those at load | suite |
| level01_probe | Rebuilt level 1: overhead layout shot + player-eye shot toward the nexus tower | windowed |
| level01_task_probe | Level 1's single checklist task (gate lever) spawns live; completing it unseals the exit | headless |
| level_detail_probe | Eye-level views of a campaign level to judge/iterate environmental detail | windowed |
| level_shot | Elevated 3/4 view of each campaign level: layout/detail/obstacle fit | windowed |
| level_sky_probe | Horizon/sky of a real open-sky night level: stars+moon | windowed |
| lightning_probe | Storm-lightning bolt at real in-game distance with fog/exposure as in play | windowed |
| limbloss_probe | Bone-collapse dismemberment: critical-threshold limb sever, LIMB_LOSS_MAX cap, no-skeleton chassis no-ops cleanly | headless |
| look_capture | Eye-level forward-looking screenshot of each campaign level for visual audit | windowed |
| loot_probe | Flyer supply drops over open sea relocate onto a walkway, never stranded in the hazard | suite |
| lowhealth_screenshot | Post-process shader with `low_health` forced high | windowed |
| mantle_kick_probe | A successful mantle fires the new viewmodel kick (not just that mantling still works) | headless |
| manus_rooted_probe | ROOTED MANUS: holds spawn position at range, finger-eruption telegraph damage, grab is now a yank within grab_reach | headless |
| map_probe | Campaign map fully unlocked: lava/water sectors, hazard rings, act grouping, drifting motes | windowed |
| map_shot | Campaign map driven by keyboard cursor: selection reticle + sector intel | windowed |
| mauler_overload_probe | MAULER's wounded OVERLOAD sprint actually bumps live `move_speed` (was a dead `_speed_mult` write) | suite |
| mech_shot | Freshly-sourced Quaternius Mech idle pose: scale/orientation before building an enemy from it | windowed |
| melee_probe | Melee shove: in-cone enemies take damage+knockback, out-of-range ones don't | headless |
| mender_probe | MENDER flies to a wounded android and beam-heals it, flight/death without errors | headless |
| menu_probe | Main menu scene exercises its `_ready` path | windowed |
| menu_screenshot | Main menu captured | windowed |
| mission_arc_probe | Every level def's task graph: unique ids, "after" refs resolve (no self-refs/cycles), positions inside floor, reinforcement types exist | suite |
| model_gallery_probe | Available CC0 enemy models side by side, for picking distinct bases for hazard-world flyers | windowed |
| model_mat_probe | Import-cache corruption sweep: each imported texture vs source PNG catches a garbage `.ctex` whose md5 still matches | headless |
| model_view_probe | Arbitrary model scene front/side/3-quarter, to judge its pose | windowed |
| music_check | Generated music tracks' peak/RMS/mid-high-band RMS as a proxy for audibility on small speakers | headless |
| muzzle_check_probe | New ranged enemy's Muzzle node marker vs the model's visible weapon | windowed |
| nemesis_probe | NEMESIS grudge loop: elite kill recorded, spawner substitutes the nemesis next spawn, killing it settles the grudge | headless |
| new_models_probe | Newly-added models individually rendered, to assign each an enemy role | windowed |
| newenemy_probe | Dog + server enemies lit, facing camera: look/facing/glowing eyes | windowed |
| newlevel_probe | Redesigned levels build; navmesh-reachable exit (softlock guard); eye-level shot | windowed |
| night_sky_probe | night_sky shader in a few faction palettes: starfield/Milky-Way/moon | windowed |
| objective_probe | Reworked objectives: kill_all+assassinate HVT, kill_all+hold_zone, level 1 keycard task registration | suite |
| open_house_check | OPEN building on level 1: hollow interior, solid walls, open doorway, baked walkable upper-floor navmesh | headless |
| open_house_probe | OPEN building photographed from street + inside; grapple pad exists | windowed |
| opening_distance_check | Per level, distance from the player spawn to the nearest enemy awake from the start — the campaign's own opening-room convention, and which levels break it | headless |
| overload_probe | OVERLOAD ultimate: meter charges to full, unleash damages+EMP-stuns hostiles in range, consuming empties the meter | windowed |
| pacing_sweep | Auto-player difficulty sweep across campaign levels: kills/HP%/deaths/progress per level | headless |
| pack_probe | Player walked spawn→exit, timestamping every enemy spawn to detect "pack" bursts within a time window | headless |
| particles_check | `GraphicsSettings.create_particles` sanity on both GPU and CPU particle paths | headless |
| patchnotes_probe | ROBOT OS patch notes: AIDirector emits changelog only once calibrated, GameState folds in hijacks/nemesis, consumed once | headless |
| pcss_shadow_shot | Deterministic PCSS penumbra capture (static scene, sun `light_angular_distance` 1.2) so an engine bump can be diffed for shadow changes; byte-identical run to run | windowed |
| perf_probe | Average frame time on a heavy level at each graphics tier (`PERF_TIER` env var) | windowed |
| phase0_test | Level def serialize→reload→build level_custom round-trip + custom build + pickups | headless |
| pickup_lineup | Health/ammo/weapon pickups rendered side by side | windowed |
| pickup_probe | A level's hand-placed pickups (def `"kind"` key) actually instantiate (kind/type key trap regression net) | headless |
| platform_probe | Vantage platforms + ramp corners built on the floor with a reachable ramp + nearby signage | windowed |
| player_feel_probe | Dash/hard-landing viewmodel kicks and the weapon-accurate dynamic crosshair | headless |
| playtest_probe | Real AI live: skitters hop, Ravager leap+slam, Warmech lob salvos; facing/scale/tint/projectiles | windowed |
| pointblank_los_probe | An enemy whose eye sits INSIDE the player's capsule still sees the player and keeps attacking (LOS ray now reports the shape it starts in at point-blank); a skitter pinned at zero distance: 0 bites and stuck in CHASE before, 5 bites in 6 s after | suite |
| preset_probe | `GraphicsSettings.apply_preset()`/`set_window_mode()` batch-applies the quality/render-scale/feature-toggle matrix per tier | windowed |
| projectile_fx_probe | Heavy projectile rounds (incl. glowing head-orb FX): launch, fly, detonate, trail head built, no errors | suite |
| promo_3d | Cinematic promo: fierce-enemy showcase, Tempest chain lightning, Vortex grenade implosion | windowed |
| promo_boss | GOLIATH-IX's sky-drop planetfall over Maple Grove Plaza | windowed |
| promo_codex | Enemy codex/bestiary entries | windowed |
| promo_ingame | Real FPS gameplay against a mixed enemy roster | windowed |
| promo_range | The firing range | windowed |
| promo_ui | Campaign map + armory shop | windowed |
| prop_lineup | Prop scenes lined up to eyeball model swaps | windowed |
| props_test | MeshInstance3D count across `LevelBuilder.PROP_SCENES` sanity-checks every prop scene loads | headless |
| purge_probe | "survive" wave escalation authoring drift + GPT Foundry PURGE PROTOCOL climax against silently-firing-nothing waves | headless |
| ramp_probe | Player capsule swept up every authored ramp (`test_move`) to catch lips/gaps that block walkability | headless |
| rampage_probe | RAMPAGE kill-streak: chained kills spike escalating damage/fire/speed buffs + heal + banner, collapsing on break | windowed |
| range_screenshot | Gun range captured after the builder settles | windowed |
| ravager_shot | RAVAGER beside a REAPER (same chassis, smaller): scale/tint reads as a heavier bruiser | windowed |
| reaper_hover_probe | Reaper hovers (no walk shamble) with the flyer bank | windowed |
| river_view | Themed rivers: the serpentine shape + the gap | windowed |
| robot_models_check | Every RobotModel-carrying enemy scene resolves its AnimationPlayer + configured clips and has visible meshes | headless |
| rollout_probe | Several rolled-out levels, one framed hero shot of each | windowed |
| roster_audit_probe | Every enemy spawned in labelled groups, screenshotted so model look can be compared against stats | windowed |
| roster_variety_probe | Every enemy scene is placed somewhere in the campaign; ordinary robots appear in more than one level (no cameo-only chassis) | headless |
| route_probe | spawn→exit navmesh path length + detour ratio for gated/led-route levels; fails loudly if a gate ever closes the route | headless |
| screen_shock_probe | Blast screen-warp logic: rings register, cap at 3 evicting the WEAKEST (not newest), expire, pack sane screen-UV/progress, zero out behind camera; glitch decays; post shader carries both uniforms | suite |
| screen_shock_shot | Unit-tests the warp on a static checker through `post_process.gdshader` (grain/warp/glitch zeroed so the shader is time-invariant) — writes `shock_off/mid/glitch.png` for screen_shock_verify | windowed |
| screen_shock_verify | Bins the shock_off↔shock_mid pixel diff by radius and asserts a structured ring at the expected crest — run AFTER screen_shock_shot | headless |
| screens_probe | Rebuilt computer props (terminal/server rack/lore console): CRT screens + bevels | windowed |
| sens_probe | Pause-menu mouse-sensitivity slider exists, persists to GraphicsSettings, updates the live player | windowed |
| separation_push_probe | The player's soft enemy-separation push is a velocity FLOOR capped at separation_max_speed, not a per-frame impulse: an enemy-layer body parked inside the probe moves the player at most a walk (was 10.2 m/s peak and 4.4 m in one second, enough to fling a player off a walkway) | suite |
| shark_breach_probe | RAZORFIN shark acquires a target, breaches above the surface, bites | suite |
| signature_attack_probe | K-9 pounce, MAITRE-D' cleaver throw, sentinel bomb lob, mauler overload detonation all fire | headless |
| skel_pose_probe | Candidate ArmRelaxModifier rotations on the George rig, to pick a natural arm-carry angle | windowed |
| skinned_models_probe | Skinned models rendered after playing their animation (not the misleading rest pose), framed on posed bone bounds | windowed |
| seeker_grace_probe | Opening attack grace holds against CONTACT damage: the SEEKER kamikaze defers its blast through grace, then still detonates once it lapses | suite |
| skitter_probe | SKITTER swarm around a player: rush in, bite, die cleanly | headless |
| sky_screenshot | SkyTraffic system with forced meteors, sky view captured | windowed |
| smasher_probe | BEHEMOTH-X with a player stand-in, real AI: wake/charge/smash | windowed |
| smasher_view_probe | BEHEMOTH-X in preview mode: the cover-art look | windowed |
| sound_id_probe | Every sound id referenced by literal in scripts/ (play_synth_at/ui, synth, play_music, play_ambience_layer, play_lore, level `music` keys) and every weapon .tres sound_id (+_fire) resolves through AudioBus.synth; a never-registered id is a silent event (caught the Armory's silent purchase clink) | suite |
| stamina_probe | Sprint/grapple stamina drains to exhaustion (walk-only lock), regen + lock clear; HUD bar screenshotted | windowed |
| startle_probe | Startle-scatter affects only in-radius non-boss non-EMP units; GODLIKE/OVERLOAD broadcasts it | headless |
| suburb_nav_diag | Which leg of the suburb canal crossing fails, chaining spawn→bridgeheads→deck→exit plus the tower route | headless |
| suburb_screenshot | Player camera walked up to a house on the suburb level, captured | windowed |
| survival_probe | Reckless-bot regression net for the onboarding survival experience (auto-reload, aggro rings, health-on-kill) | suite |
| spawn_safety_probe | Campaign-wide spawn safety: the idle player takes zero damage during the opening attack grace on every level. Also reports post-grace incoming DPS per level, blamed by source, on a deep health pool so the figure is not censored by the player dying (~155s, run deliberately) | headless |
| swarm_probe | Homing swarm missile steers into an off-axis enemy target | headless |
| synth_probe | Every key procedural sound generates non-silent, non-degenerate audio | suite |
| task_reach_probe | Every authored level-1 task position resolves clear of solid geometry and near the navmesh | headless |
| teach_probe | Each first-encounter teaching hint fires once, repeats suppressed, a new run re-arms them | suite |
| terminator_beam_probe | TERMINATOR's Optic Lance charges/fires/tracks/renders/burns the player | windowed |
| terminator_entrance_probe | TERMINATOR's eruption entrance (buried rumble→breach→rise→settle) | windowed |
| tesla_beam_probe | Holding the trigger, the Tesla's ElectricBeam activates | suite |
| tesla_ingame_probe | Full-chain Tesla-beam-in-play via the real player's WeaponManager trigger | windowed |
| threat_probe | Ground-truth per-enemy DPS on the player (report-only, real per-enemy attack vars, not scripted defaults) | headless |
| titan_blink_probe | PROMETHEUS-0's phase-blink beam charges (`BLINK_BEAM_TELL`) before sweeping instead of firing instantly undodgeable | suite |
| titan_ingame_probe | Real `titan.tscn` instantiated, sky-drop cancelled, planted boss screenshotted | windowed |
| titan_pose_probe | TITAN model front/side render + mesh-part AABB dump, to identify the arm cluster | windowed |
| tracer_screenshot | Enemy bolts + a player tracer fired across the view mid-flight | windowed |
| tree_probe | Suburb level with scattered volumetric trees at eye level | windowed |
| ttk_probe | Ground-truth weapon DPS against real enemy robots (pellets/falloff/pierce/splash/chain/cluster all counted) | headless |
| unique_enemy_probe | Batch-5 signature behaviors on real AI: hunter blade dash, raptor strafing run, ripper spin-up saw, sentinel salvo, warbot crossfire | headless |
| victory_probe | Clearing the last campaign level routes to the victory cutscene VIA the loading screen (asserts the destination, not the next frame) | suite |
| victory_watch | Helper parented to `/root`; polls `current_scene` across the campaign-end scene swaps for victory_probe | headless |
| victory_shot | Victory finale at fixed timeline moments (headless renders black) | windowed |
| voice_probe | Every `AudioBus.VOICE_CATEGORIES` clip resolves on disk; `play_voice_at` fires; per-family pack resolution + fallback works | suite |
| wallrun_probe | Sprinting into a wall engages wall-run (tangent velocity hold); wall-jump launches with expected carry | headless |
| warbot_face_probe | WAR-BOT's mood face flips green/happy idle to red/angry once it engages the player | suite |
| warbot_view_probe | Warbot's happy-idle then angry-combat face, for tuning procedural face/cannon offsets | windowed |
| weakpoint_probe | Shot-up android bares a glowing crit core on first panel shed; near-core hits read the bonus multiplier; core doesn't survive the wreck | headless |
| weapon_codex_probe | Weapon Codex layout/stats screenshotted | windowed |
| weapon_fx_probe | Laser-beam-into-wall and rocket-in-flight FX, mid-flight and post-detonation | windowed |
| weapon_lineup | Every player weapon scene with real models, rendered in a grid | windowed |
| weapon_order_probe | Weapon rack auto-sorts weakest→strongest; HUD carousel builds a cell per weapon | headless |
| weapon_pacing_probe | Weapons are first offered in campaign in power-rank order (no weaker gun handed out after a stronger one) | headless |
| weapon_recover_probe | Every way the equipped weapon can "vanish" is injected; WeaponManager watchdog notices + re-arms the player | headless |
| weapon_stats_probe | Every weapon's WeaponData is sane (guards a `.tres` regression silently shipping a broken gun) | suite |
| weapon_vanish_probe | Reproduces "I shoot/get shot and lose my weapons": rack watched every frame for null/invisible/shrinking/index-drift | headless |
| weaponfx_probe | TEMPEST chain lightning + VORTEX grenade implosion fired into a real crowd, effects captured live | windowed |

### Candidates to add to the suite

These print the real `RESULT PASS` / `RESULT FAIL` convention `run_tests.sh`
greps for, run fully headless, and are not currently wired into
`tools/run_tests.sh`'s `PROBES` array:

- `checkpoint_probe` — checkpoint/respawn flow
- `convoy_playtest` — Highway Breakout winnability
- `enemy_scale_probe` — enemy visual-height regression
- `model_mat_probe` — texture import-cache corruption sweep

The remaining `headless` entries above are mostly older report-only /
diagnostic tools (measurement sweeps, data dumps, `*_DONE` sentinels) that
predate the `RESULT PASS` convention or are deliberately noisy/exploratory —
they're not silently-broken suite gaps, just a different genre of probe.

## Probe-writing rules

Learned the hard way (see root `CLAUDE.md` and probe post-mortems):

- **Spawn a floor.** A `StaticBody3D` with collision layer 1, or every
  `CharacterBody3D` falls forever and position/range assertions lie.
- **Sample with short timer loops (0.25–0.3 s)**, not one long
  `SceneTreeTimer` await — a single long await stalls autoload `_process`
  ticking headless.
- **`get_tree().change_scene_*` frees the probe scene itself.** Run watchers
  from a node parented directly under root, not under the scene being
  replaced.
- **Probes default to LOW graphics quality.** Any probe judging detail
  density, shadow budget, or other tier-gated visuals must explicitly force
  HIGH (see `level_detail_probe.gd`) or it's silently probing the wrong tier.
- **`save_png` can hang headless.** Screenshot/render probes need a real
  window — `--headless` either renders black or, worse, blocks. Name the
  probe `*_shot` / `*_screenshot` and run it windowed (`godot --path .`).
- **Behavior probes need a navmesh + facing, or enemies freeze.** A bare
  probe arena has no baked navmesh, so an enemy that relies on pathing can't
  acquire the player — spawn it already in range/facing (see
  `enemy_behavior_probe.gd`, `enemy_combat_probe.gd`).
- **`add_child` deferred where the base class expects it.** Some base classes
  (spawners, `EnemyBase` subclasses) assume they're not yet inside the tree
  during setup; adding them immediately instead of via
  `call_deferred("add_child", …)` triggers "get_node from outside the tree"
  errors (see `elite_probe.gd`).
- **`Elite.apply` / `apply_nemesis` must run before `add_child`** — stat
  multipliers applied after the enemy enters the tree get clobbered by
  `_sync_stats`.
- **Time a bot or a measurement in GAME seconds, not wall-clock.**
  `create_timer` counts real time, but everything a probe observes — enemy
  attack cadence, weapon bloom decay, `first_shot_delay`, `equip_time`, recoil
  settle — advances on the game clock. When a machine cannot hold the physics
  rate, Godot clamps physics steps per frame and game time falls behind
  wall-clock, so a wall-clock wait leaves the world in a *different state* than
  the probe assumed, by an amount that depends on how loaded the machine is.
  This is why a probe calibrated on a dev box flakes only in CI. Await
  `get_tree().physics_frame` and accumulate `get_physics_process_delta_time()`
  instead (see `_wait_game` in `survival_probe.gd` / `gun_range_probe.gd`).
  It caused every CI failure in a 30-run stretch.
- **A statistical gate needs a real sample, and must print `n`.** A mean over a
  handful of samples is not evidence. Report the sample size in the assertion
  message and fail loudly when it is too small, rather than averaging whatever
  survived — a thinned sample otherwise reads as a genuine measurement.
  Widening a flaky gate's threshold treats the symptom; find what makes the
  measurement environment-dependent and remove it.
- A **freed instance compares EQUAL to null** but `is`/property access still
  raise — guard with `is_instance_valid(x)`, never `x != null`.

## Maintenance

Adding a new logic probe? Add it to the `PROBES` array in
`tools/run_tests.sh` **and** to the table above (probe name, one-line
"verifies", mode). If it can't run headless, mark it `windowed` here instead
of adding it to the suite.
