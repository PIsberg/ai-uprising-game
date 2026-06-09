# Sampled-audio overrides

Drop a real audio file here named exactly after a sound id and it will be used
in place of the procedural synth for that sound — no code changes needed. The
synth (`scripts/autoload/sound_synth.gd`) remains the fallback when no file is
present, so the game always has sound.

- Naming: `<id>.ogg`, `<id>.wav`, or `<id>.mp3` (probed in that order).
- Resolved by `AudioBus.synth()` → `_resolve_sample()` (cached after first probe).

Sound ids currently in use:
`pistol_fire, rifle_fire, shotgun_fire, plasma_fire, drone_shot, rocket_fire,
empty_click, reload, pump_action, footstep, impact_metal, impact_concrete,
drone_hum, mech_step, pickup_health, pickup_ammo, explosion, grenade_throw,
eas_alert, broadcast_blip, radio_static, music_techno, ambience_drone,
ambience_wind`

Example: add `pistol_fire.ogg` here and every pistol shot uses it.

Source CC0 packs that fit (download + drop in): Kenney "Sci-Fi Sounds" /
"Impact Sounds", or freesound.org CC0 clips.
