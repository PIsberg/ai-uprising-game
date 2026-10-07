extends Node
## SoundSynth must not hold up boot. It synthesizes every sound in GDScript
## (57 streams, 9.3 MB of PCM); done in its autoload _ready that took 4.3 s of
## the 5.1 s before the first frame on the dev machine, a blank window on every
## launch. Generation now runs on a worker thread, and get_stream() builds any
## stream that is not ready yet on the spot, so no caller ever gets silence.
##
## Checks: re-running SoundSynth._ready() returns within READY_BUDGET_MS; right
## after it, every stream id resolves to non-empty PCM; the background pass
## finishes; and the menu theme AudioBus starts at boot is playing.
##   godot --headless --path . --audio-driver Dummy res://tests/synth_boot_probe.tscn

const READY_BUDGET_MS := 1000.0
const FINISH_TIMEOUT_S := 30.0

var _ok := true

func _ready() -> void:
	_run.call_deferred()

func _ids() -> Array:
	if SoundSynth.has_method("ids"):
		return SoundSynth.ids()
	return SoundSynth.streams.keys()

func _all_ready() -> bool:
	if SoundSynth.has_method("is_all_ready"):
		return SoundSynth.is_all_ready()
	return true

func _run() -> void:
	var t0 := Time.get_ticks_usec()
	SoundSynth._ready()
	var ready_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("SoundSynth._ready: %.0f ms (budget %.0f)" % [ready_ms, READY_BUDGET_MS])
	if ready_ms > READY_BUDGET_MS:
		_bad("SoundSynth._ready blocked for %.0f ms" % ready_ms)

	var ids := _ids()
	if ids.size() < 50:
		_bad("only %d stream ids registered" % ids.size())
	var t1 := Time.get_ticks_usec()
	var empty := 0
	for id in ids:
		var s = SoundSynth.get_stream(id)
		if not (s is AudioStreamWAV) or (s as AudioStreamWAV).data.size() < 200:
			empty += 1
			print("BAD  %s: no stream right after boot" % id)
	print("all %d ids resolved in %.0f ms (on-demand where not ready yet)" % [ids.size(), (Time.get_ticks_usec() - t1) / 1000.0])
	if empty > 0:
		_bad("%d ids had no stream" % empty)

	var waited := 0.0
	while not _all_ready() and waited < FINISH_TIMEOUT_S:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if not _all_ready():
		_bad("background synthesis not finished after %.0f s" % FINISH_TIMEOUT_S)

	var music: AudioStreamPlayer = AudioBus.get("_music")
	var playing := music != null and music.stream != null and music.playing
	print("menu music: id=%s playing=%s" % [AudioBus.get("_current_music_id"), playing])
	if not playing:
		_bad("the boot theme is not playing")

	print("RESULT %s" % ("PASS" if _ok else "FAIL"))
	get_tree().quit(0 if _ok else 1)

func _bad(msg: String) -> void:
	_ok = false
	print("BAD  " + msg)
