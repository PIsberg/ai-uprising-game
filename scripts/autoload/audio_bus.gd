# @lat: [[architecture#Autoloads#AudioBus and SoundSynth]]
extends Node


# Positional-SFX voice pool. Sized so a dense firefight (or a swarm caught in a
# blast) doesn't round-robin over still-playing voices and cut its own sounds —
# 16 saturated the instant a mega-bomb killed a cluster. 24 gives headroom without
# meaningfully taxing the audio mixer.
const POOL_SIZE := 24

var _pool: Array[AudioStreamPlayer3D] = []
var _next: int = 0

## When true, positional world SFX (play_at / play_voice_at / play_synth_at) are
## dropped. The level editor sets this so preview-instanced enemies stay silent —
## which also stops their in-flight playbacks leaking when the tool quits.
var suppress_world_sfx := false
var _synth: Node
var _music: AudioStreamPlayer
var _ui: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _ambience2: AudioStreamPlayer # optional hazard bed layered over the room tone

# Sampled-audio override: any real file at assets/audio/samples/<id>.<ext> is
# used in place of the procedural synth for that id (synth stays the fallback).
# Lets the project ship synth audio now and drop in real foley later, no code
# changes — this is the hook for the sampled-audio pass.
const SAMPLE_DIR := "res://assets/audio/samples/"
const SAMPLE_EXTS := [".ogg", ".wav", ".mp3"]
var _sample_cache: Dictionary = {}

func _ready() -> void:
	# Buses must exist before players reference them by name.
	_setup_buses()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 80.0
		p.unit_size = 4.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		# Routed through "SFXReverb" (not "SFX" directly) so every positional
		# world sound — footsteps, weapon impacts, enemy locomotion ticks —
		# picks up the level's environmental reverb. See _setup_reverb_bus.
		p.bus = "SFXReverb"
		add_child(p)
		_pool.append(p)
	# Non-positional players for music + UI/broadcast. process_mode ALWAYS so the
	# broadcast intro can play while the game tree is paused.
	_music = AudioStreamPlayer.new()
	_music.volume_db = MUSIC_CALM_DB
	_music.bus = "Music"
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)
	_ui = AudioStreamPlayer.new()
	_ui.bus = "SFX"
	_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui)
	_ambience = AudioStreamPlayer.new()
	_ambience.volume_db = -20.0
	_ambience.bus = "SFX"
	add_child(_ambience)
	_ambience2 = AudioStreamPlayer.new()
	_ambience2.volume_db = -24.0
	_ambience2.bus = "SFX"
	add_child(_ambience2)
	_setup_broadcast_bus()
	_setup_robot_voice_bus()
	for i in VOICE_POOL_SIZE:
		var vp := AudioStreamPlayer3D.new()
		vp.max_distance = 60.0
		vp.unit_size = 5.0
		vp.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		vp.bus = "RobotVoice"
		add_child(vp)
		_voice_pool.append(vp)
	_index_voice_clips()
	_load_volume()

## Quit teardown: stop every player so no AudioStreamPlayback objects are
## still owned by the mixer when the engine checks for leaked resources at
## exit (a robot mid-bark at quit otherwise trips "resources still in use",
## which CI treats as a failure).
func _exit_tree() -> void:
	for p in _pool:
		p.stop()
		p.stream = null
	for p in _voice_pool:
		p.stop()
		p.stream = null
	for p in [_music, _ui, _ambience, _ambience2, _lore_player]:
		if p:
			p.stop()
			p.stream = null
	_voice_clips.clear()
	_sample_cache.clear()

## Creates the Music and SFX buses (each routed to Master) if they don't exist,
## so a global Master slider still scales everything while Music/SFX get their
## own independent sliders.
func _setup_buses() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_ensure_master_limiter()
	_setup_reverb_bus()
	# Start the looping theme once, unconditionally — NOT as a side effect of a
	# bus being freshly created (which silently skipped music whenever the buses
	# already existed). Deferred so SoundSynth's _ready has built its streams.
	_start_music.call_deferred()

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")

## Transparent brick-wall limiter on Master so a peak moment — stacked
## explosions + gunfire + a full horde + the music swell — can't sum past 0 dB
## into harsh digital clipping right when the action is loudest. Idempotent.
func _ensure_master_limiter() -> void:
	var master := AudioServer.get_bus_index("Master")
	if master < 0:
		return
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			return
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.0
	AudioServer.add_bus_effect(master, lim)

# ---------- environmental reverb (positional world SFX only) ----------
# A dedicated "SFXReverb" bus that the _pool players (footsteps, weapon
# impacts/tracers, pickups, enemy locomotion ticks — every play_at/play_synth_at
# call) route through, sitting between them and "SFX". Music, Broadcast, UI and
# the ambience bed all send straight to "SFX" and never pass through this bus,
# so corridors/interiors can ring without smearing the score or menu blips.
const REVERB_INDOOR := {"room_size": 0.42, "damping": 0.2, "wet": 0.22}
const REVERB_OUTDOOR := {"room_size": 0.9, "damping": 0.85, "wet": 0.05}

func _setup_reverb_bus() -> void:
	if AudioServer.get_bus_index("SFXReverb") != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "SFXReverb")
	AudioServer.set_bus_send(idx, "SFX") # still scaled by the SFX slider + Master limiter
	var rv := AudioEffectReverb.new()
	rv.room_size = REVERB_OUTDOOR["room_size"]
	rv.damping = REVERB_OUTDOOR["damping"]
	rv.wet = REVERB_OUTDOOR["wet"]
	AudioServer.add_bus_effect(idx, rv)

## Switch the positional-SFX reverb between a tight, ringy indoor room and a
## faint, dry outdoor space. Levels call this once at build time from the same
## indoor/outdoor signal that already picks the ambience bed (def "open_sky").
func set_reverb_environment(indoor: bool) -> void:
	var p: Dictionary = REVERB_INDOOR if indoor else REVERB_OUTDOOR
	set_reverb_wet(p["wet"], p["room_size"], p["damping"])

## Cheap direct setter so cutscenes/specific levels can hand-tune the room feel
## beyond the two stock presets above (wet 0..1).
func set_reverb_wet(wet: float, room_size: float = 0.5, damping: float = 0.5) -> void:
	var idx := AudioServer.get_bus_index("SFXReverb")
	if idx < 0:
		return
	for i in AudioServer.get_bus_effect_count(idx):
		var fx := AudioServer.get_bus_effect(idx, i)
		if fx is AudioEffectReverb:
			(fx as AudioEffectReverb).room_size = room_size
			(fx as AudioEffectReverb).damping = damping
			(fx as AudioEffectReverb).wet = clampf(wet, 0.0, 1.0)
			return

# ---------- blast shock (close explosion -> muffle + tinnitus) ----------
# An explosion near the player's head low-passes the positional world mix (the
# SFXReverb bus: gunfire, impacts, footsteps) and ducks the score while a thin
# ear-ring whine plays, all recovering over a couple of seconds. UI/confirm
# cues route around the muffle on the plain SFX bus, so feedback stays crisp
# while the WORLD goes underwater — the standard modern-shooter deafen.

const SHOCK_RADIUS := 13.0     ## full->zero shock over this distance to the blast
const SHOCK_RECOVERY := 0.45   ## shock units shed per second (~2.2 s full recovery)
const SHOCK_MIN := 0.25        ## blasts farther than ~75% of the radius don't ring
const SHOCK_LP_HZ := 650.0     ## low-pass floor at full shock
const SHOCK_OPEN_HZ := 20500.0 ## effectively transparent
const SHOCK_MUSIC_DUCK_DB := 9.0

var _shock: float = 0.0
var _shock_lp: AudioEffectLowPassFilter

## Report an explosion at a world position. Fired automatically for every
## "explosion" played through play_synth_at; scripted set-piece blasts can call
## it directly (strength scales the felt radius).
func notify_blast(position: Vector3, strength: float = 1.0) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var d := cam.global_position.distance_to(position)
	var intensity := clampf(1.0 - d / SHOCK_RADIUS, 0.0, 1.0) * clampf(strength, 0.0, 1.5)
	if intensity < SHOCK_MIN or intensity <= _shock:
		return
	_shock = minf(intensity, 1.0)
	# The whine plays on the (unmuffled) UI channel so it survives its own muffle.
	play_synth_ui("ear_ring", lerpf(-18.0, -8.0, _shock), randf_range(0.96, 1.04))
	# Both pad motors slam with the blast and trail off with the deafen.
	Haptics.pulse(_shock * 0.8, _shock, 0.5)

## Lazily insert the muffle low-pass on SFXReverb (kept transparent at rest).
func _ensure_shock_lp() -> AudioEffectLowPassFilter:
	if _shock_lp:
		return _shock_lp
	var idx := AudioServer.get_bus_index("SFXReverb")
	if idx < 0:
		return null
	_shock_lp = AudioEffectLowPassFilter.new()
	_shock_lp.cutoff_hz = SHOCK_OPEN_HZ
	AudioServer.add_bus_effect(idx, _shock_lp)
	return _shock_lp

# ---------- per-bus volume (persisted to user://settings.cfg) ----------

const SETTINGS_PATH := "user://settings.cfg"

## Apply a 0..1 linear slider value to a bus and persist it under audio/<key>.
func _set_bus_linear(bus_name: String, linear: float, key: String) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("audio", key, clampf(linear, 0.0, 1.0))
	cf.save(SETTINGS_PATH)

func _get_bus_linear(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 1.0
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.0, 1.0)

func set_master_volume(linear: float) -> void:
	_set_bus_linear("Master", linear, "master")

func get_master_volume() -> float:
	return _get_bus_linear("Master")

func set_sfx_volume(linear: float) -> void:
	_set_bus_linear("SFX", linear, "sfx")

func get_sfx_volume() -> float:
	return _get_bus_linear("SFX")

## Linear (0..1) Music bus control for the settings slider. (`set_music_volume`
## below stays as a raw-dB internal helper.)
func set_music_volume_linear(linear: float) -> void:
	_set_bus_linear("Music", linear, "music")

func get_music_volume() -> float:
	return _get_bus_linear("Music")

func _load_volume() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	_apply_loaded(cf, "Master", "master")
	_apply_loaded(cf, "SFX", "sfx")
	_apply_loaded(cf, "Music", "music")

func _apply_loaded(cf: ConfigFile, bus_name: String, key: String) -> void:
	var v: float = cf.get_value("audio", key, 1.0)
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(v, 0.0001, 1.0)))
		AudioServer.set_bus_mute(idx, v <= 0.001)

## A "Broadcast" bus that band-passes (carving out lows + highs like a small
## speaker) and lightly distorts whatever is routed to it, so the intro VO sounds
## like it's coming through damaged comms gear. The voice + static bed use it.
func _setup_broadcast_bus() -> void:
	if AudioServer.get_bus_index("Broadcast") != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "Broadcast")
	AudioServer.set_bus_send(idx, "Master")
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 520.0
	AudioServer.add_bus_effect(idx, hp)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 3000.0
	AudioServer.add_bus_effect(idx, lp)
	var dist := AudioEffectDistortion.new()
	dist.mode = AudioEffectDistortion.MODE_OVERDRIVE
	dist.drive = 0.3
	dist.pre_gain = 4.0
	dist.post_gain = -4.0
	AudioServer.add_bus_effect(idx, dist)

# ---------- robot voice lines ----------
# Pre-generated TTS clips (tools/gen_voices.ps1 -> assets/audio/voice/) played
# positionally through the "RobotVoice" bus, whose pitch-drop + ring of
# distortion turns the plain TTS into machine speech. A global cooldown keeps a
# squad of robots from talking over each other into mush.

const VOICE_POOL_SIZE := 4
const VOICE_DIR := "res://assets/audio/voice/"
## Category -> clip count. Keys match the wav prefixes from gen_voices.ps1.
const VOICE_CATEGORIES := {
	"spot": 8, "atk": 9, "hurt": 6, "die": 16, "taunt": 24,
	# Per-family personality packs (EnemyBase tries "<family>_<cat>" first and
	# falls back to the generic pool above). Counts mirror tools/gen_voices.ps1.
	"dog_spot": 2, "dog_atk": 3, "dog_die": 2,
	"sniper_spot": 2, "sniper_atk": 2, "sniper_die": 1,
	"mender_spot": 1, "mender_atk": 3, "mender_die": 2,
	"mech_spot": 1, "mech_atk": 2, "mech_die": 1,
	"drone_spot": 1, "drone_atk": 2, "drone_die": 1,
}

var _voice_pool: Array[AudioStreamPlayer3D] = []
var _voice_next: int = 0
var _voice_clips: Dictionary = {} # category -> Array[AudioStream]
var _voice_cooldown_until: float = 0.0
var _voice_last_clip: Dictionary = {} # category -> last index, avoids repeats

func _setup_robot_voice_bus() -> void:
	if AudioServer.get_bus_index("RobotVoice") != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "RobotVoice")
	AudioServer.set_bus_send(idx, "SFX") # scaled by the SFX volume slider
	# Drop the TTS a few semitones: bigger, more machine.
	var ps := AudioEffectPitchShift.new()
	ps.pitch_scale = 0.82
	ps.oversampling = 4
	AudioServer.add_bus_effect(idx, ps)
	# Light overdrive adds a synthetic buzz to the vowels.
	var dist := AudioEffectDistortion.new()
	dist.mode = AudioEffectDistortion.MODE_OVERDRIVE
	dist.drive = 0.22
	dist.pre_gain = 2.0
	dist.post_gain = -2.0
	AudioServer.add_bus_effect(idx, dist)
	# Small-speaker band-pass: it's coming out of a robot chassis, not a studio.
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 320.0
	AudioServer.add_bus_effect(idx, hp)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 5200.0
	AudioServer.add_bus_effect(idx, lp)

func _index_voice_clips() -> void:
	for cat: String in VOICE_CATEGORIES:
		var clips: Array = []
		for i: int in VOICE_CATEGORIES[cat]:
			var path := "%s%s_%d.wav" % [VOICE_DIR, cat, i]
			if ResourceLoader.exists(path):
				clips.append(load(path))
		_voice_clips[cat] = clips

## Speak a random clip from `category` at a world position. Returns true if a
## line actually played. `chance` rolls the dice first so callers can say
## "sometimes"; the global cooldown then keeps overlapping squads coherent.
## Death lines bypass the cooldown — a kill should always get its payoff.
func play_voice_at(category: String, position: Vector3, chance: float = 1.0, volume_db: float = 2.0, pitch: float = 1.0) -> bool:
	if suppress_world_sfx or randf() > chance:
		return false
	var clips: Array = _voice_clips.get(category, [])
	if clips.is_empty():
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if not category.ends_with("die") and now < _voice_cooldown_until:
		return false
	_voice_cooldown_until = now + randf_range(1.6, 2.8)
	var idx := randi() % clips.size()
	if clips.size() > 1 and idx == int(_voice_last_clip.get(category, -1)):
		idx = (idx + 1) % clips.size()
	_voice_last_clip[category] = idx
	var p := _voice_pool[_voice_next]
	_voice_next = (_voice_next + 1) % VOICE_POOL_SIZE
	p.stream = clips[idx]
	p.global_position = position
	p.volume_db = volume_db
	# Family pitch identity (dogs chirp, mechs rumble) with a per-bark wobble on
	# top of the bus shift so units don't sound cloned.
	p.pitch_scale = pitch * randf_range(0.92, 1.12)
	p.play()
	return true

# ---------- lore log playback ----------
# Faction data-log VO (tools/gen_lore.ps1 -> assets/audio/lore/). Routed
# through the band-passed "Broadcast" bus so logs sound like recovered
# recordings on damaged equipment.

const LORE_DIR := "res://assets/audio/lore/"
var _lore_player: AudioStreamPlayer

func play_lore(id: String) -> void:
	var path := LORE_DIR + id + ".wav"
	if not ResourceLoader.exists(path):
		return
	if _lore_player == null:
		_lore_player = AudioStreamPlayer.new()
		_lore_player.bus = "Broadcast"
		_lore_player.volume_db = 4.0
		add_child(_lore_player)
	_lore_player.stream = load(path)
	_lore_player.play()

var _current_music_id: String = ""
var _music_enabled := true   # editor disables the looping theme; re-enabled on exit

# Adaptive intensity: the score reacts to how HOT the fight is — louder and a
# touch brighter as more hostiles engage — swelling fast when a fight kicks off
# and settling slowly when it clears.
var _combat: float = 0.0       ## smoothed heat 0..1
var _combat_target: float = 0.0
const MUSIC_CALM_DB := -12.0
const MUSIC_COMBAT_DB := -6.0
const MUSIC_HOT_DB := -3.0     ## peak-battle bump

## Back-compat binary entry point (maps to full / no heat).
func set_combat(active: bool) -> void:
	set_combat_heat(1.0 if active else 0.0)

## Reactive intensity. heat 0 = calm exploration, 1 = peak battle (a swarm of
## active hostiles). The HUD feeds this from the live enemy count.
func set_combat_heat(heat: float) -> void:
	_combat_target = clampf(heat, 0.0, 1.0)

## Fraction the score steps back while a broadcast/lore VO line is speaking.
var _vo_duck: float = 0.0
const VO_DUCK_DB := 7.0

func _process(delta: float) -> void:
	if _music == null:
		return
	# Swell fast on engagement, settle slowly when it clears.
	var rate := 2.2 if _combat_target > _combat else 0.45
	_combat = move_toward(_combat, _combat_target, delta * rate)
	# Any engagement lifts CALM->COMBAT quickly; a big fight pushes toward HOT.
	var base := lerpf(MUSIC_CALM_DB, MUSIC_COMBAT_DB, clampf(_combat * 2.0, 0.0, 1.0))
	var vol := lerpf(base, MUSIC_HOT_DB, smoothstep(0.5, 1.0, _combat))
	# VO duck: the score steps back while a lore/broadcast line is speaking
	# (fast dip, gentle recovery) so the voice never fights the music.
	var speaking := _lore_player != null and _lore_player.playing
	_vo_duck = move_toward(_vo_duck, 1.0 if speaking else 0.0, delta * (6.0 if speaking else 1.8))
	vol -= VO_DUCK_DB * _vo_duck
	# Blast shock: shed intensity, duck the score and run the world low-pass
	# from wide open down toward the muffle floor as shock deepens.
	if _shock > 0.0:
		_shock = maxf(0.0, _shock - delta * SHOCK_RECOVERY)
		vol -= SHOCK_MUSIC_DUCK_DB * _shock
		var lp := _ensure_shock_lp()
		if lp:
			# Perceptual sweep: interpolate in log-frequency so the recovery
			# sounds even instead of hanging muffled then snapping open.
			lp.cutoff_hz = exp(lerpf(log(SHOCK_OPEN_HZ), log(SHOCK_LP_HZ), pow(_shock, 1.2)))
	elif _shock_lp and _shock_lp.cutoff_hz < SHOCK_OPEN_HZ:
		_shock_lp.cutoff_hz = SHOCK_OPEN_HZ
	_music.volume_db = vol
	_music.pitch_scale = lerpf(1.0, 1.09, _combat)

func _start_music() -> void:
	if not _music_enabled:
		return
	play_music("music_techno")
	# If the synth wasn't ready yet (stream unresolved), play_music is a no-op and
	# _current_music_id stays empty — retry next frame so launch is never silent.
	if _current_music_id == "":
		_start_music.call_deferred()

## Turn the looping music on/off (the level editor mutes it while editing, then
## restores it on exit/playtest). Disabling stops the player and clears the
## current track so re-enabling restarts the theme cleanly.
func set_music_enabled(on: bool) -> void:
	_music_enabled = on
	if on:
		_start_music()
	else:
		if _music:
			_music.stop()
		_current_music_id = ""

## Switch the looping music to a themed track (e.g. per level). No-op if that
## track is already playing, so re-entering a level doesn't restart the loop.
func play_music(id: String) -> void:
	if _music == null or not _music_enabled or id == _current_music_id:
		return
	var stream := synth(id)
	if stream == null:
		return
	_current_music_id = id
	_music.stream = stream
	_music.play()

func set_music_volume(db: float) -> void:
	if _music:
		_music.volume_db = db

func play_synth_ui(id: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	var stream := synth(id)
	if stream == null or _ui == null:
		return
	_ui.stream = stream
	_ui.volume_db = volume_db
	_ui.pitch_scale = pitch_scale
	_ui.play()

func play_at(stream: AudioStream, position: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null or suppress_world_sfx:
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.global_position = position
	p.volume_db = volume_db
	p.pitch_scale = pitch_scale
	p.play()

## Runtime lookup so scripts don't need to statically depend on the SoundSynth autoload.
func _get_synth() -> Node:
	if _synth and is_instance_valid(_synth):
		return _synth
	_synth = get_tree().root.get_node_or_null("SoundSynth")
	return _synth

func synth(id: String) -> AudioStream:
	# Prefer a real sample file if one exists; otherwise use the synth.
	var sample := _resolve_sample(id)
	if sample:
		return sample
	var s := _get_synth()
	if s and s.has_method("get_stream"):
		return s.get_stream(id)
	return null

## Look up assets/audio/samples/<id>.<ext>; caches the result (null included) so
## the filesystem is only probed once per id.
func _resolve_sample(id: String) -> AudioStream:
	if _sample_cache.has(id):
		return _sample_cache[id]
	var found: AudioStream = null
	for ext in SAMPLE_EXTS:
		var path: String = SAMPLE_DIR + id + ext
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is AudioStream:
				found = res
				break
	_sample_cache[id] = found
	return found

## Looping atmospheric bed for a level (room tone / wind), fading in softly so
## a level swap never hard-cuts the loop edge. Starting a new room tone also
## clears any hazard layer — every level build calls this, so a lava bed can't
## leak into the next, lava-less, level.
func play_ambience(id: String, volume_db: float = -20.0) -> void:
	if _ambience2 and _ambience2.playing:
		_ambience2.stop()
	_play_bed(_ambience, id, volume_db)

## Second, optional bed layered OVER the room tone (lava bubbling under the
## drone, water flow under the wind) so a hazard level reads by ear before the
## hazard is even in view. Call after play_ambience.
func play_ambience_layer(id: String, volume_db: float = -24.0) -> void:
	_play_bed(_ambience2, id, volume_db)

func _play_bed(p: AudioStreamPlayer, id: String, volume_db: float) -> void:
	if p == null:
		return
	var stream := synth(id)
	if stream == null:
		return
	p.stream = stream
	p.volume_db = -50.0
	p.play()
	var tw := create_tween()
	tw.tween_property(p, "volume_db", volume_db, 1.2)

func stop_ambience() -> void:
	if _ambience:
		_ambience.stop()
	if _ambience2:
		_ambience2.stop()

func play_synth_at(id: String, position: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	var stream := synth(id)
	if stream:
		play_at(stream, position, volume_db, pitch_scale)
	# Every explosion in the game funnels through here — piggyback the blast
	# shock so no per-call-site wiring is needed for the deafen effect.
	if id == "explosion" and not suppress_world_sfx:
		notify_blast(position)
