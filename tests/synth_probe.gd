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
		var s: AudioStreamWAV = SoundSynth.get_stream(id)
		if s == null:
			print("MISSING %s" % id); ok = false; continue
		var data: PackedByteArray = s.data
		var nsamp := data.size() / 2
		var peak := 0.0
		var sumsq := 0.0
		for i in nsamp:
			var v := float(data.decode_s16(i * 2)) / 32768.0
			peak = maxf(peak, absf(v))
			sumsq += v * v
		var rms := sqrt(sumsq / float(maxi(nsamp, 1)))
		print("%-16s samples=%6d peak=%.3f rms=%.3f" % [id, nsamp, peak, rms])
		# Non-silent, audible, and within range (s16 can't exceed 1.0).
		if nsamp < 100 or peak < 0.2 or peak > 1.001 or rms < 0.01:
			ok = false
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
