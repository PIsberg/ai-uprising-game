extends Node
## Sampled-audio overrides (AudioBus._resolve_sample, assets/audio/samples/).
## (1) every sample file in the folder is named after a real SoundSynth id (a typo
##     would silently never play) and numbered takes run 0..n without gaps;
## (2) an id with several takes resolves to an AudioStreamRandomizer holding all
##     of them in PLAYBACK_RANDOM_NO_REPEATS mode (the engine does the no-repeat);
## (3) an id with no file still gets the synth stream.
##   godot --headless --path . --audio-driver Dummy res://tests/sample_override_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	var ids := {}
	for id in SoundSynth.ids():
		ids[id] = true
	var takes := {} # id -> highest take index + 1 seen
	var counts := {} # id -> number of take files
	var files := 0
	for f in DirAccess.get_files_at(AudioBus.SAMPLE_DIR):
		var ext := "." + f.get_extension()
		if not ext in AudioBus.SAMPLE_EXTS:
			continue
		files += 1
		var base := f.get_basename()
		var id := base
		var parts := base.rsplit("_", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int() and not ids.has(base):
			id = parts[0]
			takes[id] = maxi(int(takes.get(id, 0)), int(parts[1]) + 1)
			counts[id] = int(counts.get(id, 0)) + 1
		_check("'%s' overrides a real synth id" % f, ids.has(id))
	for id in takes:
		_check("%s takes are numbered without gaps" % id, takes[id] == counts[id], "%d files, highest %d" % [counts[id], takes[id] - 1])
	_check("the folder ships samples", files > 0, "%d files" % files)

	for id in counts:
		var s := AudioBus.synth(id)
		var n := int(counts[id])
		if n > 1:
			var r := s as AudioStreamRandomizer
			_check("%s resolves to a no-repeat randomizer of %d takes" % [id, n],
				r != null and r.streams_count == n and r.playback_mode == AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS)
		else:
			_check("%s resolves to its one sample" % id, s is AudioStreamOggVorbis or s is AudioStreamWAV or s is AudioStreamMP3)

	var synth_only := "pistol_fire"
	_check("an id with no sample keeps the synth", not counts.has(synth_only) and AudioBus.synth(synth_only) is AudioStreamWAV)

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
