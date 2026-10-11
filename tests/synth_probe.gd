extends Node
## Dev probe: sanity-checks the procedural audio after the quality pass. Can't judge
## how it SOUNDS, but verifies each key sound generates non-silent and non-degenerate
## (reasonable peak + RMS, within 16-bit range) — i.e. the synth math didn't break.
##   godot --headless --path . res://tests/synth_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ok := true
	var ids := ["pistol_fire", "rifle_fire", "shotgun_fire", "gauss_fire",
		"explosion", "impact_metal", "impact_concrete", "music_techno"]
	for id in ids:
		var got := SoundSynth.get_stream(id)
		# A music theme is synced stems (AudioBus layers them): judge what plays
		# with every layer up, their sum, and require each stem to be non-silent.
		var parts: Array[AudioStreamWAV] = []
		if got is AudioStreamSynchronized:
			var sync := got as AudioStreamSynchronized
			for k in sync.stream_count:
				parts.append(sync.get_sync_stream(k) as AudioStreamWAV)
		else:
			parts.append(got as AudioStreamWAV)
		if parts.has(null):
			print("MISSING %s" % id); ok = false; continue
		var nsamp := parts[0].data.size() / 2
		var peak := 0.0
		var sumsq := 0.0
		var stem_sq: Array[float] = []
		stem_sq.resize(parts.size())
		stem_sq.fill(0.0)
		for i in nsamp:
			var v := 0.0
			for k in parts.size():
				var x := float(parts[k].data.decode_s16(i * 2)) / 32768.0
				v += x
				stem_sq[k] += x * x
			peak = maxf(peak, absf(v))
			sumsq += v * v
		for k in parts.size():
			if parts.size() > 1 and sqrt(stem_sq[k] / float(maxi(nsamp, 1))) < 0.01:
				print("%s stem %d is silent" % [id, k]); ok = false
		var rms := sqrt(sumsq / float(maxi(nsamp, 1)))
		print("%-16s samples=%6d peak=%.3f rms=%.3f" % [id, nsamp, peak, rms])
		# Non-silent, audible, and within range (s16 can't exceed 1.0).
		if nsamp < 100 or peak < 0.2 or peak > 1.001 or rms < 0.01:
			ok = false
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
