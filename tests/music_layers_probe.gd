extends Node
## Probe: the level themes play as synced layers that follow the fight.
## (1) every synth theme is an AudioStreamSynchronized of four looping stems
##     (bed, drums, lead, hot) of equal length, none of them silent;
## (2) calm (combat heat 0): the bed plays, the drums are down at least 24 dB,
##     the lead sits under it and the hot layer is silent;
## (3) a fight (heat 1): drums and lead come up to full;
## (4) a RAMPAGE tier brings in the hot layer; losing the streak takes it out;
## (5) a live boss brings it in too;
## (6) the synced theme loops: still playing, and wrapped, past its length.
## Read through AudioBus.music_layer_db(name), the volume the mixer is given.
##   godot --headless --path . --audio-driver Dummy res://tests/music_layers_probe.tscn

const THEMES := ["music_techno", "music_grok", "music_gemini", "music_archon",
	"music_lava", "music_water", "music_suburb"]
const LAYERS := ["bed", "drums", "lead", "hot"]
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _wait(sec: float) -> void:
	var n := int(ceil(sec / 0.25))
	for i in n:
		await get_tree().create_timer(0.25).timeout

func _ready() -> void:
	_run.call_deferred()

func _rms(w: AudioStreamWAV) -> float:
	var data := w.data
	var n := data.size() / 2
	var sumsq := 0.0
	for i in range(0, n, 7): # every 7th sample is plenty for a level
		var v := data.decode_s16(i * 2) / 32768.0
		sumsq += v * v
	return sqrt(sumsq / maxf(n / 7.0, 1.0))

func _sum_peak(sync: AudioStreamSynchronized) -> float:
	var datas: Array[PackedByteArray] = []
	for k in sync.stream_count:
		datas.append((sync.get_sync_stream(k) as AudioStreamWAV).data)
	var peak := 0.0
	for i in datas[0].size() / 2:
		var v := 0.0
		for d in datas:
			v += d.decode_s16(i * 2) / 32768.0
		peak = maxf(peak, absf(v))
	return peak

func _db(layer: String) -> float:
	if not AudioBus.has_method("music_layer_db"):
		return NAN
	return AudioBus.call("music_layer_db", layer)

func _run() -> void:
	# The mixer names the stems in the order the synth renders them.
	var synth_names: Array = SoundSynth.get_script().get_script_constant_map().get("MUSIC_LAYERS", [])
	var bus_names: Array = AudioBus.get_script().get_script_constant_map().get("MUSIC_LAYERS", [])
	_check("synth and mixer agree on the stem order", synth_names == LAYERS and bus_names == LAYERS,
		"synth %s, mixer %s" % [synth_names, bus_names])
	# 1. Stems.
	for id: String in THEMES:
		var s := SoundSynth.get_stream(id)
		var sync := s as AudioStreamSynchronized
		_check("%s is synced layers" % id, sync != null and sync.stream_count == LAYERS.size(),
			"got %s" % (s.get_class() if s else "null"))
		if sync == null:
			continue
		var sizes := {}
		var quiet: Array[String] = []
		for i in sync.stream_count:
			var w := sync.get_sync_stream(i) as AudioStreamWAV
			if w == null or w.loop_mode != AudioStreamWAV.LOOP_FORWARD:
				quiet.append("%d:not a looping wav" % i)
				continue
			sizes[w.data.size()] = true
			var r := _rms(w)
			if r < 0.01:
				quiet.append("%s rms %.3f" % [LAYERS[i], r])
		_check("%s stems loop at one length and none is silent" % id, sizes.size() == 1 and quiet.is_empty(),
			"lengths %s %s" % [sizes.keys(), quiet])
		# Every layer up (a boss fight in a rampage): loud, but never clipping.
		if sizes.size() == 1 and quiet.is_empty():
			var peak := _sum_peak(sync)
			_check("%s full mix peaks in 0.3-1.0" % id, peak >= 0.3 and peak <= 1.0, "peak %.3f" % peak)

	# 2. Calm.
	AudioBus.play_music("music_grok")
	GameState.rampage_tier = 0
	AudioBus.set_combat_heat(0.0)
	await _wait(4.0)
	_check("calm: the bed plays", _db("bed") > -1.0, "bed %.1f dB" % _db("bed"))
	_check("calm: drums are down", _db("drums") <= -24.0, "drums %.1f dB" % _db("drums"))
	_check("calm: the lead sits under", _db("lead") <= -8.0 and _db("lead") > -30.0, "lead %.1f dB" % _db("lead"))
	_check("calm: the hot layer is silent", _db("hot") <= -40.0, "hot %.1f dB" % _db("hot"))

	# 3. A fight.
	AudioBus.set_combat_heat(1.0)
	await _wait(2.5)
	_check("fight: drums come in", _db("drums") > -1.0, "drums %.1f dB" % _db("drums"))
	_check("fight: the lead comes up", _db("lead") > -1.0, "lead %.1f dB" % _db("lead"))
	_check("fight: still no hot layer without a streak", _db("hot") <= -40.0, "hot %.1f dB" % _db("hot"))

	# 4. RAMPAGE.
	GameState.rampage_tier = 1
	await _wait(2.0)
	_check("rampage: the hot layer comes in", _db("hot") > -1.0, "hot %.1f dB" % _db("hot"))
	GameState.rampage_tier = 0
	AudioBus.set_combat_heat(0.0)
	await _wait(5.0)
	_check("streak lost and calm: hot layer out again", _db("hot") <= -40.0, "hot %.1f dB" % _db("hot"))
	_check("calm again: drums down again", _db("drums") <= -24.0, "drums %.1f dB" % _db("drums"))

	# 5. A live boss.
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	cs.shape = bs
	cs.position.y = -0.5
	floor_body.add_child(cs)
	add_child(floor_body)
	var boss := (load("res://scenes/enemies/smasher.tscn") as PackedScene).instantiate() as EnemyBase
	add_child(boss)
	GameState.boss_spawned.emit(boss)
	await _wait(2.0)
	_check("boss alive: the hot layer comes in", _db("hot") > -1.0, "hot %.1f dB" % _db("hot"))
	boss.queue_free()
	await _wait(5.0)
	_check("boss gone: hot layer out", _db("hot") <= -40.0, "hot %.1f dB" % _db("hot"))

	# 6. Loops past its end (techno: 16 beats at 128 bpm = 7.5 s).
	AudioBus.play_music("music_techno")
	var player: AudioStreamPlayer = AudioBus.get("_music")
	var length := player.stream.get_length() if player and player.stream else 0.0
	# Sample the playback position until it jumps back (a wrap) or 3x the
	# length passes: the dummy driver's audio clock need not match wall time.
	var last := -1.0
	var wrapped := false
	var top := 0.0
	var t_end := Time.get_ticks_msec() + int(length * 3000.0)
	while player != null and Time.get_ticks_msec() < t_end:
		await get_tree().create_timer(0.25).timeout
		var pos := player.get_playback_position()
		top = maxf(top, pos)
		if last >= 0.0 and pos < last - 1.0:
			wrapped = true
			break
		last = pos
	await _wait(0.5)
	_check("the theme loops past its %.1f s length" % length, player != null and length > 1.0 and wrapped and player.playing,
		"wrapped=%s (top %.2f s) playing=%s" % [wrapped, top, player.playing if player else false])

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
