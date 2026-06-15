extends Node3D
## Analyse the generated music tracks: peak + overall RMS + mid/high-band RMS
## (a rough proxy for "audible on small speakers" — the melody/hats vs sub-bass).
##   godot --headless --path . tests/music_check.tscn

func _ready() -> void:
	await get_tree().process_frame
	for id in ["music_techno", "music_grok", "music_gemini", "music_archon", "music_suburb"]:
		var s := AudioBus.synth(id) as AudioStreamWAV
		if s == null:
			print(id, ": <null>")
			continue
		var data := s.data
		var n := data.size() / 2
		var peak := 0.0
		var sumsq := 0.0
		var prev := 0.0
		var hp_sumsq := 0.0  # crude high-pass (diff) energy ~ mid/high content
		for i in n:
			var v := data.decode_s16(i * 2) / 32768.0
			peak = maxf(peak, absf(v))
			sumsq += v * v
			var hp := v - prev
			hp_sumsq += hp * hp
			prev = v
		var rms := sqrt(sumsq / maxf(n, 1))
		var hp_rms := sqrt(hp_sumsq / maxf(n, 1))
		print("%-14s peak=%.2f rms=%.3f mid/high=%.3f" % [id, peak, rms, hp_rms])
	get_tree().quit()
