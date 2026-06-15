extends Node3D
## Headless check: does AudioBus actually start music at boot?
## Run as a scene so autoloads (AudioBus, SoundSynth) load:
##   godot --headless --path . tests/music_check.tscn

func _ready() -> void:
	# Reproduce the real start: bring up the actual main menu scene, which shares
	# the AudioBus autoload, then watch what happens to music over ~2s.
	var menu := (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().create_timer(2.0).timeout

	print("Master vol dB = ", AudioServer.get_bus_volume_db(0), " muted=", AudioServer.is_bus_mute(0))
	print("Music bus idx = ", AudioServer.get_bus_index("Music"))
	print("Music bus muted = ", AudioServer.is_bus_mute(maxi(AudioServer.get_bus_index("Music"), 0)))
	print("Music bus vol dB = ", AudioServer.get_bus_volume_db(maxi(AudioServer.get_bus_index("Music"), 0)))
	print("current_music_id = '", AudioBus._current_music_id, "'")
	print("_music valid = ", is_instance_valid(AudioBus._music))
	if is_instance_valid(AudioBus._music):
		print("_music.playing = ", AudioBus._music.playing)
		print("_music.stream = ", AudioBus._music.stream)
		print("_music.volume_db = ", AudioBus._music.volume_db)
	var s = AudioBus.synth("music_techno")
	print("synth('music_techno') = ", s, "  len=", (s.get_length() if s else -1.0))
	get_tree().quit()
