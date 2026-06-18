extends Node
## Procedural audio synthesizer. Generates AudioStreamWAV samples at startup
## so the project ships with sound without bundling .ogg/.wav files.

const SR := 44100

var streams: Dictionary = {}

func _ready() -> void:
	streams["pistol_fire"] = _gun_fire(0.22, 240.0, 0.9, 1.6, false)
	streams["rifle_fire"] = _gun_fire(0.18, 180.0, 0.7, 1.4, false)
	streams["shotgun_fire"] = _gun_fire(0.35, 120.0, 1.2, 2.0, true)
	streams["plasma_fire"] = _plasma_fire(0.4)
	streams["drone_shot"] = _laser_zap(0.18, 1400.0, 600.0)
	streams["rocket_fire"] = _rocket_fire(0.55)
	streams["empty_click"] = _click(0.12, 1800.0)
	streams["reload"] = _reload_chunk(0.45)
	streams["pump_action"] = _pump(0.35)
	streams["footstep"] = _footstep(0.16)
	streams["impact_metal"] = _impact(0.12, 0.6)
	streams["impact_concrete"] = _impact(0.16, 0.3)
	streams["drone_hum"] = _drone_hum(1.2)
	streams["mech_step"] = _mech_step(0.32)
	streams["pickup_health"] = _chime(0.3, 660.0, 990.0)
	streams["pickup_ammo"] = _pickup_clink(0.22)
	streams["explosion"] = _explosion(0.7)
	streams["grenade_throw"] = _whoosh(0.25)
	streams["eas_alert"] = _eas_alert(1.4)
	streams["broadcast_blip"] = _broadcast_blip(0.14)
	streams["victory"] = _victory_sting(1.3)
	streams["combo_up"] = _combo_up(0.34)
	streams["headshot"] = _headshot_ding(0.18)
	streams["overlord_glitch"] = _glitch_comms(0.32)
	streams["acid_spit"] = _acid_spit(0.3)
	streams["radio_static"] = _radio_static(1.6)
	streams["music_techno"] = _techno_loop()
	streams["music_grok"] = _music_grok()
	streams["music_gemini"] = _music_gemini()
	streams["music_suburb"] = _music_suburb()
	streams["music_archon"] = _music_archon()
	streams["ambience_drone"] = _ambient_drone(4.0)
	streams["ambience_wind"] = _ambient_wind(4.0)
	streams["breathing"] = _breathing(4.0)

func get_stream(id: String) -> AudioStream:
	return streams.get(id)

# ----- ambience beds (seamless 4s loops) -----

## Low industrial room tone: stacked low sines + slow swell + faint air hiss.
func _ambient_drone(dur: float) -> AudioStreamWAV:
	var n := int(SR * dur)
	var bytes := _silence(n)
	for i in n:
		var t := float(i) / SR
		var swell := 0.5 + 0.5 * sin(TAU * 0.25 * t) # whole cycle over 4s -> seamless
		var s := sin(TAU * 55.0 * t) * 0.5
		s += sin(TAU * 82.5 * t) * 0.22
		s += sin(TAU * 110.0 * t) * 0.16
		s += (randf() * 2.0 - 1.0) * 0.03 # faint hiss
		s *= 0.55 + 0.45 * swell
		_write(bytes, i, s * 0.45)
	return _to_stream(bytes, true)

## Outdoor wind: low-passed noise with slow gusting.
func _ambient_wind(dur: float) -> AudioStreamWAV:
	var n := int(SR * dur)
	var bytes := _silence(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var white := randf() * 2.0 - 1.0
		lp = lp * 0.96 + white * 0.04 # one-pole low-pass -> wind rush
		var gust := 0.5 + 0.5 * sin(TAU * 0.25 * t)
		_write(bytes, i, lp * (0.35 + 0.65 * gust) * 0.7)
	return _to_stream(bytes, true)

## Exhausted breathing (low-health loop): two breaths per seamless 4s cycle —
## a brighter, shorter inhale hiss and a softer, longer exhale, both made of
## filtered noise so it reads as breath, not wind.
func _breathing(dur: float) -> AudioStreamWAV:
	var n := int(SR * dur)
	var bytes := _silence(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / SR
		var cycle := fmod(t, 2.0) # one full breath every 2 seconds
		var env := 0.0
		var bright := 0.0
		if cycle < 0.75:
			env = sin(PI * cycle / 0.75) # inhale: short, sharp
			bright = 0.55
		elif cycle >= 0.95:
			env = sin(PI * (cycle - 0.95) / 1.05) * 0.85 # exhale: longer, softer
			bright = 0.22
		var white := randf() * 2.0 - 1.0
		lp = lp * (0.93 - bright * 0.28) + white * (0.07 + bright * 0.28)
		lp2 = lp2 * 0.55 + lp * 0.45 # second pole rounds off the hiss
		_write(bytes, i, lp2 * env * env * 0.9)
	return _to_stream(bytes, true)

# ----- helpers -----

static func _silence(n: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	return bytes

static func _write(bytes: PackedByteArray, idx: int, sample: float) -> void:
	var v := int(clampf(sample, -1.0, 1.0) * 32700.0)
	bytes.encode_s16(idx * 2, v)

static func _to_stream(bytes: PackedByteArray, loop: bool = false) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SR
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = bytes.size() / 2
	return s

# ----- generators -----

func _gun_fire(duration: float, body_hz: float, body_amp: float, click_amp: float, deep: bool) -> AudioStreamWAV:
	# Sharp click + body thump + decaying mid-noise
	var n := int(duration * SR)
	var bytes := _silence(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		var env_click := exp(-t * 90.0)
		var env_body := exp(-t * (18.0 if deep else 30.0))
		var env_tail := exp(-t * 9.0) * (1.0 - exp(-t * 60.0))
		# Body thump (low sine sweep)
		var hz := body_hz * (1.0 - 0.4 * (1.0 - env_body))
		phase += TAU * hz / SR
		var body := sin(phase) * body_amp * env_body
		# Click (broadband noise multiplied by very fast decay)
		var click := (randf() * 2.0 - 1.0) * click_amp * env_click
		# Mid-band noise tail
		var tail := (randf() * 2.0 - 1.0) * 0.35 * env_tail
		var s := tanh(body + click + tail) * 0.85
		_write(bytes, i, s)
	return _to_stream(bytes)

func _plasma_fire(duration: float) -> AudioStreamWAV:
	# Pitched zap with rising sweep + crackle
	var n := int(duration * SR)
	var bytes := _silence(n)
	var phase_a := 0.0
	var phase_b := 0.0
	for i in n:
		var t := float(i) / SR
		var env := exp(-t * 8.0) * (1.0 - exp(-t * 120.0))
		var hz_a := 220.0 + 700.0 * (1.0 - exp(-t * 6.0))
		var hz_b := hz_a * 2.02
		phase_a += TAU * hz_a / SR
		phase_b += TAU * hz_b / SR
		var tone := sin(phase_a) * 0.6 + sin(phase_b) * 0.3
		var crackle := (randf() * 2.0 - 1.0) * 0.25 * env
		var s := tanh(tone * env + crackle) * 0.9
		_write(bytes, i, s)
	return _to_stream(bytes)

func _laser_zap(duration: float, hz_start: float, hz_end: float) -> AudioStreamWAV:
	var n := int(duration * SR)
	var bytes := _silence(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		var u := t / duration
		var env := exp(-t * 14.0) * (1.0 - exp(-t * 200.0))
		var hz := lerpf(hz_start, hz_end, u)
		phase += TAU * hz / SR
		var s := sin(phase) * 0.7 * env + (randf() * 2.0 - 1.0) * 0.12 * env
		_write(bytes, i, s)
	return _to_stream(bytes)

func _rocket_fire(duration: float) -> AudioStreamWAV:
	# Whoosh: filtered noise with low rumble
	var n := int(duration * SR)
	var bytes := _silence(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var env := pow(sin(PI * (t / duration)), 0.6)
		var hz := 80.0 + 30.0 * sin(t * 8.0)
		phase += TAU * hz / SR
		var rumble := sin(phase) * 0.5
		var noise := randf() * 2.0 - 1.0
		# One-pole lowpass
		lp = lerpf(lp, noise, 0.18)
		var s := (lp * 0.7 + rumble * 0.6) * env
		_write(bytes, i, tanh(s))
	return _to_stream(bytes)

func _click(duration: float, hz: float) -> AudioStreamWAV:
	var n := int(duration * SR)
	var bytes := _silence(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		var env := exp(-t * 45.0)
		phase += TAU * hz / SR
		var s := (sin(phase) * 0.5 + (randf() * 2.0 - 1.0) * 0.6) * env
		_write(bytes, i, s)
	return _to_stream(bytes)

func _reload_chunk(duration: float) -> AudioStreamWAV:
	# Two metallic clicks separated in time
	var n := int(duration * SR)
	var bytes := _silence(n)
	for i in n:
		var t := float(i) / SR
		var c1 := exp(-pow((t - 0.05) * 25.0, 2.0))
		var c2 := exp(-pow((t - 0.28) * 22.0, 2.0))
		var s := (randf() * 2.0 - 1.0) * (c1 * 0.8 + c2 * 0.7)
		_write(bytes, i, s)
	return _to_stream(bytes)

func _pump(duration: float) -> AudioStreamWAV:
	# Cha-chunk: slide back (rasp) then forward (clack)
	var n := int(duration * SR)
	var bytes := _silence(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var rasp := exp(-pow((t - 0.07) * 8.0, 2.0))
		var clack := exp(-pow((t - 0.24) * 30.0, 2.0))
		var noise := randf() * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.4)
		var s := lp * rasp * 0.6 + (randf() * 2.0 - 1.0) * clack * 0.95
		_write(bytes, i, s)
	return _to_stream(bytes)

func _footstep(duration: float) -> AudioStreamWAV:
	# Low thud + scuffed mid noise
	var n := int(duration * SR)
	var bytes := _silence(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var env := exp(-t * 18.0)
		phase += TAU * 90.0 / SR
		var body := sin(phase) * 0.5 * env
		var noise := randf() * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.25)
		var s := (body + lp * 0.4 * env) * 0.8
		_write(bytes, i, s)
	return _to_stream(bytes)

func _impact(duration: float, brightness: float) -> AudioStreamWAV:
	var n := int(duration * SR)
	var bytes := _silence(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var env := exp(-t * 28.0)
		var noise := randf() * 2.0 - 1.0
		lp = lerpf(lp, noise, clampf(brightness, 0.05, 0.95))
		var s := lp * env * 0.9
		_write(bytes, i, s)
	return _to_stream(bytes)

func _drone_hum(duration: float) -> AudioStreamWAV:
	# Looped: two close detuned saws + vibrato
	var n := int(duration * SR)
	var bytes := _silence(n)
	var pa := 0.0
	var pb := 0.0
	var pv := 0.0
	for i in n:
		var t := float(i) / SR
		pv += TAU * 6.0 / SR
		var vib := sin(pv) * 0.018
		var hz_a := 110.0 * (1.0 + vib)
		var hz_b := 113.0 * (1.0 + vib)
		pa += TAU * hz_a / SR
		pb += TAU * hz_b / SR
		# Sawtooth via wrap
		var sa := fposmod(pa, TAU) / TAU * 2.0 - 1.0
		var sb := fposmod(pb, TAU) / TAU * 2.0 - 1.0
		# Soft fade in/out at the loop edges
		var fade := 1.0
		var fade_len := 0.02
		if t < fade_len:
			fade = t / fade_len
		elif t > duration - fade_len:
			fade = (duration - t) / fade_len
		var s := (sa * 0.35 + sb * 0.35) * 0.6 * fade
		_write(bytes, i, s)
	return _to_stream(bytes, true)

func _explosion(duration: float) -> AudioStreamWAV:
	# Low boom + bright crack + decaying noise rumble.
	var n := int(duration * SR)
	var bytes := _silence(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var env := exp(-t * 6.0)
		var crack := (randf() * 2.0 - 1.0) * exp(-t * 40.0) * 0.9
		var hz := 70.0 * exp(-t * 4.0) + 30.0
		phase += TAU * hz / SR
		var boom := sin(phase) * env
		var noise := randf() * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.15)
		var rumble := lp * env * 0.6
		_write(bytes, i, tanh(boom + crack + rumble) * 0.95)
	return _to_stream(bytes)

func _whoosh(duration: float) -> AudioStreamWAV:
	# Short airy throw whoosh (band-passed noise swelling then fading).
	var n := int(duration * SR)
	var bytes := _silence(n)
	var lp := 0.0
	var hp := 0.0
	for i in n:
		var t := float(i) / SR
		var env := sin(PI * (t / duration))
		var noise := randf() * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.3)
		hp = lp - hp * 0.5
		_write(bytes, i, hp * env * 0.5)
	return _to_stream(bytes)

func _eas_alert(duration: float) -> AudioStreamWAV:
	# Emergency-alert attention signal: two alternating tones (853/960 Hz).
	var n := int(duration * SR)
	var bytes := _silence(n)
	var pa := 0.0
	var pb := 0.0
	for i in n:
		var t := float(i) / SR
		pa += TAU * 853.0 / SR
		pb += TAU * 960.0 / SR
		# Alternate the two tones every 0.25s like a real alert header.
		var which := int(t / 0.25) % 2
		var tone := sin(pa) if which == 0 else sin(pb)
		var fade := 1.0
		if t < 0.02:
			fade = t / 0.02
		elif t > duration - 0.05:
			fade = (duration - t) / 0.05
		_write(bytes, i, tone * 0.5 * fade)
	return _to_stream(bytes)

func _broadcast_blip(duration: float) -> AudioStreamWAV:
	# Robotic comms blip used as each broadcast line appears.
	var n := int(duration * SR)
	var bytes := _silence(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		var env := exp(-t * 22.0) * (1.0 - exp(-t * 300.0))
		var hz := 480.0 + 220.0 * sin(t * 60.0)
		phase += TAU * hz / SR
		var s := (sign_wave(phase) * 0.4 + sin(phase) * 0.4) * env
		_write(bytes, i, s)
	return _to_stream(bytes)

static func sign_wave(phase: float) -> float:
	return 1.0 if sin(phase) >= 0.0 else -1.0

func _radio_static(duration: float) -> AudioStreamWAV:
	# Looped radio hiss + intermittent crackle pops, for the broadcast bed.
	var n := int(duration * SR)
	var bytes := _silence(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var noise := randf() * 2.0 - 1.0
		lp = lerpf(lp, noise, 0.4)
		var hiss := (noise - lp) * 0.25 # high-passed hiss
		var crackle := 0.0
		if randf() < 0.0025:
			crackle = (randf() * 2.0 - 1.0) * 0.7
		var fade := 1.0
		var fl := 0.03
		if t < fl:
			fade = t / fl
		elif t > duration - fl:
			fade = (duration - t) / fl
		_write(bytes, i, (hiss + crackle) * fade)
	return _to_stream(bytes, true)

func _techno_loop() -> AudioStreamWAV:
	# The original driving techno loop, now expressed via the parameterised
	# generator below. Kept as the default / menu theme.
	var roots := [55.0, 55.0, 65.41, 73.42, 55.0, 55.0, 49.0, 65.41,
		55.0, 55.0, 65.41, 73.42, 82.41, 73.42, 65.41, 49.0]
	var arp := [220.0, 261.63, 329.63, 261.63, 246.94, 329.63, 392.0, 329.63]
	return _music_track(128.0, roots, arp, {})

## Parameterised 16-step music loop so each level theme gets its own track from
## the same engine. `roots` is the per-step bass note, `arp` the lead sequence;
## `p` tweaks the mix (kick/bass/arp/hat/pad levels, drive, swing, arp division,
## saw-vs-square bass). All tracks share the four-on-the-floor backbone but read
## very differently via tempo, key and instrumentation.
func _music_track(bpm: float, roots: Array, arp: Array, p: Dictionary) -> AudioStreamWAV:
	var spb := 60.0 / bpm
	var total_beats := roots.size()
	var dur := spb * total_beats
	var n := int(dur * SR)
	var bytes := _silence(n)
	var kick_lvl: float = p.get("kick", 0.82)
	var bass_lvl: float = p.get("bass", 0.22)
	var arp_lvl: float = p.get("arp", 0.2)
	var hat_lvl: float = p.get("hat", 0.14)
	var pad_lvl: float = p.get("pad", 0.05)
	var drive: float = p.get("drive", 0.9)
	var saw_bass: bool = p.get("saw_bass", true)
	var arp_div: float = p.get("arp_div", 0.5) # 0.5 = eighths, 0.25 = sixteenths
	var bass_phase := 0.0
	var arp_phase := 0.0
	var pad_a := 0.0
	var pad_b := 0.0
	for i in n:
		var t := float(i) / SR
		var beat_idx := int(t / spb) % total_beats
		var beat_t: float = fmod(t, spb)
		var half_t: float = fmod(t, spb * 0.5)
		var root: float = roots[beat_idx]
		# Kick — four on the floor.
		var kick_env := exp(-beat_t * 24.0)
		var kick_hz := 110.0 * exp(-beat_t * 16.0) + 45.0
		var kick := sin(TAU * kick_hz * beat_t) * kick_env * kick_lvl
		# Bass, eighth-note gated (saw or square).
		bass_phase += TAU * root / SR
		var bass_wave := (fposmod(bass_phase, TAU) / TAU * 2.0 - 1.0) if saw_bass else sign_wave(bass_phase)
		var bass := bass_wave * bass_lvl * exp(-half_t * 5.0)
		# Lead arp — a square plus an octave-up sine sparkle so the melody sits in
		# the mids/highs and cuts through on any speaker (the old thin square at a
		# low level vanished under the sub-bass kick on small speakers).
		var step := int(t / (spb * arp_div)) % arp.size()
		var arp_freq: float = arp[step]
		arp_phase += TAU * arp_freq / SR
		var arp_env := exp(-fmod(t, spb * arp_div) * 8.0)
		var arp_s := (sign_wave(arp_phase) * 0.7 + sin(arp_phase * 2.0) * 0.4) * arp_lvl * arp_env
		# Soft sustained pad (root + fifth) for atmosphere.
		var pad := 0.0
		if pad_lvl > 0.0:
			pad_a += TAU * root * 0.5 / SR
			pad_b += TAU * root * 0.75 / SR
			pad = (sin(pad_a) + sin(pad_b) * 0.7) * pad_lvl
		# Offbeat hats.
		var hat := (randf() * 2.0 - 1.0) * exp(-half_t * 80.0) * hat_lvl
		var fade := 1.0
		if t < 0.012:
			fade = t / 0.012
		elif t > dur - 0.012:
			fade = (dur - t) / 0.012
		_write(bytes, i, tanh((kick + bass + arp_s + hat + pad) * drive) * 0.9 * fade)
	return _to_stream(bytes, true)

## Aggressive boss/black-site theme: faster, darker key, pounding kick, gritty
## drive, sixteenth-note arp.
func _music_grok() -> AudioStreamWAV:
	var roots := [55.0, 55.0, 58.27, 49.0, 55.0, 55.0, 65.41, 61.74,
		49.0, 49.0, 55.0, 58.27, 65.41, 61.74, 55.0, 49.0]
	var arp := [110.0, 164.81, 220.0, 164.81, 130.81, 196.0, 261.63, 196.0]
	return _music_track(142.0, roots, arp, {
		"kick": 0.85, "bass": 0.26, "arp": 0.18, "hat": 0.15,
		"drive": 1.15, "pad": 0.06, "arp_div": 0.25,
	})

## ARCHON finale theme: slow, crushing and dread-laden — sub-bass roots, a
## pounding kick, a big dark pad and a sparse, cold minor arp. The sound of one
## mind running everything.
func _music_archon() -> AudioStreamWAV:
	var roots := [36.71, 36.71, 43.65, 49.0, 36.71, 36.71, 41.2, 38.89,
		32.7, 32.7, 38.89, 43.65, 49.0, 43.65, 41.2, 36.71]
	var arp := [146.83, 220.0, 293.66, 220.0, 174.61, 233.08, 293.66, 233.08]
	return _music_track(96.0, roots, arp, {
		"kick": 0.9, "bass": 0.3, "arp": 0.15, "hat": 0.13,
		"drive": 1.2, "pad": 0.13, "arp_div": 0.25,
	})

## Airy, brighter Gemini theme: relaxed tempo, square bass, lush pad, melodic arp.
func _music_gemini() -> AudioStreamWAV:
	var roots := [65.41, 65.41, 82.41, 98.0, 73.42, 73.42, 87.31, 98.0,
		65.41, 65.41, 82.41, 110.0, 98.0, 87.31, 82.41, 73.42]
	var arp := [261.63, 329.63, 392.0, 493.88, 392.0, 329.63, 440.0, 329.63]
	return _music_track(122.0, roots, arp, {
		"kick": 0.68, "bass": 0.16, "arp": 0.22, "hat": 0.12,
		"drive": 0.8, "pad": 0.1, "saw_bass": false,
	})

## Brooding dusk-suburb theme: slow, sparse, heavy on the pad, light percussion.
func _music_suburb() -> AudioStreamWAV:
	var roots := [49.0, 49.0, 55.0, 65.41, 49.0, 49.0, 58.27, 55.0,
		43.65, 43.65, 49.0, 55.0, 58.27, 55.0, 49.0, 43.65]
	var arp := [196.0, 233.08, 293.66, 233.08, 174.61, 220.0, 293.66, 220.0]
	return _music_track(104.0, roots, arp, {
		"kick": 0.78, "bass": 0.18, "arp": 0.14, "hat": 0.08,
		"drive": 0.85, "pad": 0.11,
	})

func _victory_sting(duration: float) -> AudioStreamWAV:
	# A short triumphant fanfare: a rising major triad (C-E-G-C) whose notes
	# enter in quick succession and ring out together. Played on level clear.
	var n := int(duration * SR)
	var bytes := _silence(n)
	var notes := [523.25, 659.25, 783.99, 1046.5] # C5 E5 G5 C6
	for i in n:
		var t := float(i) / SR
		var s := 0.0
		for k in notes.size():
			var onset := float(k) * 0.08
			if t >= onset:
				var lt := t - onset
				var ph := TAU * float(notes[k]) * lt
				var env := exp(-lt * 2.0) * (1.0 - exp(-lt * 60.0))
				var saw := fposmod(ph, TAU) / TAU * 2.0 - 1.0
				s += (saw * 0.5 + sin(ph) * 0.5) * env * 0.22
		var spark := sin(TAU * 1568.0 * t) * exp(-t * 3.0) * 0.05
		_write(bytes, i, tanh((s + spark) * 1.1))
	return _to_stream(bytes)

## Rising chiptune arpeggio for crossing a kill-streak milestone — three quick
## notes climbing (E5 → B5 → E6) with a square-wave bite and a spark on top.
func _combo_up(duration: float) -> AudioStreamWAV:
	var n := int(duration * SR)
	var bytes := _silence(n)
	var notes := [659.25, 987.77, 1318.5]
	for i in n:
		var t := float(i) / SR
		var s := 0.0
		for k in notes.size():
			var onset := float(k) * 0.06
			if t >= onset:
				var lt := t - onset
				var ph := TAU * float(notes[k]) * lt
				var env := exp(-lt * 7.0) * (1.0 - exp(-lt * 80.0))
				var sq := 1.0 if sin(ph) >= 0.0 else -1.0
				s += (sq * 0.32 + sin(ph) * 0.5) * env * 0.3
		var spark := sin(TAU * 2637.0 * t) * exp(-t * 5.0) * 0.06
		_write(bytes, i, tanh((s + spark) * 1.1))
	return _to_stream(bytes)

## Glitchy digital comms sting for the rogue-AI overlord taunts: a stuttered,
## bit-crushed square tone that slides down, smeared with a little static — the
## sound of something inhuman keying the channel.
func _glitch_comms(duration: float) -> AudioStreamWAV:
	var n := int(duration * SR)
	var bytes := _silence(n)
	for i in n:
		var t := float(i) / SR
		var env := (1.0 - exp(-t * 80.0)) * exp(-t * 6.0)
		# Choppy gate: ~50 stutter slices/sec, every third muted.
		var step := int(t * 50.0)
		var gate := 0.0 if step % 3 == 0 else 1.0
		# Descending square, then quantized hard (bit-crush bite).
		var hz := 880.0 - 560.0 * (t / duration)
		var sq: float = sign_wave(TAU * hz * t)
		var crushed: float = round(sq * 3.0) / 3.0
		var noise := (randf() * 2.0 - 1.0) * 0.12
		_write(bytes, i, tanh((crushed * 0.32 + noise) * gate * env * 1.3))
	return _to_stream(bytes)

## Wet alien acid-spit: a gurgly FM tone sliding downward under a splattery noise
## transient — an organic "ptew" that reads apart from the metal weapons.
func _acid_spit(duration: float) -> AudioStreamWAV:
	var n := int(duration * SR)
	var bytes := _silence(n)
	for i in n:
		var t := float(i) / SR
		var env := exp(-t * 9.0) * (1.0 - exp(-t * 70.0))
		var hz: float = 520.0 - 300.0 * (t / duration)
		var fm: float = sin(TAU * hz * t + sin(TAU * 48.0 * t) * 2.2) # gurgle
		var splat: float = (randf() * 2.0 - 1.0) * 0.45 * exp(-t * 22.0)
		_write(bytes, i, tanh((fm * 0.5 + splat) * env * 1.25))
	return _to_stream(bytes)

## Crisp headshot ding: a high, detuned bell ping with a fast click transient.
func _headshot_ding(duration: float) -> AudioStreamWAV:
	var n := int(duration * SR)
	var bytes := _silence(n)
	for i in n:
		var t := float(i) / SR
		var env := exp(-t * 24.0)
		var s := sin(TAU * 2100.0 * t) * 0.5 + sin(TAU * 3150.0 * t) * 0.3
		s += (randf() * 2.0 - 1.0) * exp(-t * 120.0) * 0.4
		_write(bytes, i, tanh(s * env * 1.2))
	return _to_stream(bytes)

func _chime(duration: float, hz_lo: float, hz_hi: float) -> AudioStreamWAV:
	# Rising two-tone pickup chime (low note hands off to a higher one).
	var n := int(duration * SR)
	var bytes := _silence(n)
	var pa := 0.0
	var pb := 0.0
	for i in n:
		var t := float(i) / SR
		var u := t / duration
		pa += TAU * hz_lo / SR
		pb += TAU * hz_hi / SR
		var env_lo := exp(-t * 9.0) * clampf(1.0 - u * 1.6, 0.0, 1.0)
		var env_hi := exp(-maxf(0.0, t - 0.1) * 7.0) * clampf((u - 0.25) * 2.0, 0.0, 1.0)
		var s := sin(pa) * 0.4 * env_lo + sin(pb) * 0.45 * env_hi
		_write(bytes, i, tanh(s))
	return _to_stream(bytes)

func _pickup_clink(duration: float) -> AudioStreamWAV:
	# Bright metallic double-clink for ammo.
	var n := int(duration * SR)
	var bytes := _silence(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		var c1 := exp(-pow((t - 0.02) * 40.0, 2.0))
		var c2 := exp(-pow((t - 0.11) * 38.0, 2.0))
		phase += TAU * 2200.0 / SR
		var ring := sin(phase) * 0.3
		var s := (randf() * 2.0 - 1.0) * (c1 * 0.7 + c2 * 0.6) + ring * (c1 + c2)
		_write(bytes, i, tanh(s))
	return _to_stream(bytes)

func _mech_step(duration: float) -> AudioStreamWAV:
	# Heavy boom + metallic ring
	var n := int(duration * SR)
	var bytes := _silence(n)
	var phase_low := 0.0
	var phase_ring := 0.0
	for i in n:
		var t := float(i) / SR
		var env_boom := exp(-t * 14.0)
		var env_ring := exp(-t * 7.0) * (1.0 - exp(-t * 80.0))
		phase_low += TAU * 60.0 / SR
		phase_ring += TAU * 420.0 / SR
		var boom := sin(phase_low) * env_boom
		var ring := sin(phase_ring) * 0.35 * env_ring
		var s := tanh(boom + ring) * 0.95
		_write(bytes, i, s)
	return _to_stream(bytes)
