extends Node
## Dev probe: validates the boss kill-cam time dilation.
## (1) a boss-tier kill (points >= 1000) drops Engine.time_scale to the frozen
##     depth and emits boss_killcam_started;
## (2) the ramp eases back and lands at exactly 1.0 within the duration;
## (3) sub-boss kills do NOT trigger it (flat hit_stop path unchanged);
## (4) a kill-cam outside PLAYING is refused (no stranded slow-mo).
##   godot --headless --path . res://tests/killcam_probe.tscn

var _cam_label := ""

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ok := true
	GameState.boss_killcam_started.connect(func(label: String, _d: float): _cam_label = label)

	# 1+2. Boss kill: deep dip, then eased return to exactly 1.0. Sampled with
	# SHORT waits: one long headless SceneTreeTimer stalls autoload processing
	# (a headless scheduling quirk), which starved the wall-clock ramp and
	# false-failed this probe.
	GameState.set_state(GameState.State.PLAYING)
	Engine.time_scale = 1.0
	GameState.add_kill(3000, "GOLIATH-IX")
	var dipped: float = Engine.time_scale
	var ramped := false # saw a value strictly between the dip and full speed
	for i in 12: # 12 x 0.25s wall = past the total duration
		await get_tree().create_timer(0.25, true, false, true).timeout
		var v: float = Engine.time_scale
		if v > dipped + 0.02 and v < 0.98:
			ramped = true
	var settled: float = Engine.time_scale
	print("KILLCAM: label='%s' dip=%.2f ramped=%s settled=%.2f" % [_cam_label, dipped, ramped, settled])
	if not (_cam_label == "GOLIATH-IX" and dipped <= 0.12 and ramped and settled == 1.0):
		ok = false

	# 3. A regular kill leaves the kill-cam alone.
	_cam_label = ""
	GameState.add_kill(150, "ANDROID")
	var no_cam: bool = _cam_label == "" and Engine.time_scale == 1.0
	print("REGULAR: no_killcam=%s" % no_cam)
	if not no_cam:
		ok = false

	# 4. Refused outside PLAYING.
	GameState.set_state(GameState.State.MENU)
	_cam_label = ""
	GameState.boss_killcam("X")
	var refused: bool = _cam_label == "" and Engine.time_scale == 1.0
	print("GATED: refused_in_menu=%s" % refused)
	if not refused:
		ok = false

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
