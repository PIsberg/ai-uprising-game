extends Node
## Writes every SoundSynth stream to <out>/<id>.wav so tools/import_samples.py can
## level-match a real sample against the synth sound it replaces.
##   godot --headless --path . --audio-driver Dummy res://tools/dump_synth.tscn -- --out=<abs dir>

func _ready() -> void:
	var out := ProjectSettings.globalize_path("user://synth_dump")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var n := 0
	for id in SoundSynth.ids():
		var s = SoundSynth.get_stream(id)
		if s is AudioStreamWAV:
			(s as AudioStreamWAV).save_to_wav("%s/%s.wav" % [out, id])
			n += 1
	print("dumped %d synth streams to %s" % [n, out])
	get_tree().quit()
