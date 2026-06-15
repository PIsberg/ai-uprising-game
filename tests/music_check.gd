extends Node3D
## Headless check: does music survive entering an actual level?
##   godot --headless --path . tests/music_check.tscn

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	print("BOOT current_music_id = '", AudioBus._current_music_id, "' playing=",
		(AudioBus._music.playing if is_instance_valid(AudioBus._music) else "no-player"))

	# Now bring up a real level (it builds itself + calls play_music in _ready).
	var lvl := (load("res://scenes/levels/level_01.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(1.5).timeout

	print("INLEVEL current_music_id = '", AudioBus._current_music_id, "'")
	if is_instance_valid(AudioBus._music):
		print("INLEVEL playing = ", AudioBus._music.playing,
			"  volume_db = ", AudioBus._music.volume_db,
			"  stream = ", AudioBus._music.stream)
	print("Music bus muted=", AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")),
		" dB=", AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")))
	get_tree().quit()
