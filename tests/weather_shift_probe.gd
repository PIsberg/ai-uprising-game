extends Node3D
## Weather shifts (weather_shift.gd): a survive wave's "weather" thickens the
## level's fog by fog_mult, shifts its colour and gusts the weather particles,
## then eases every value back to where it started when the hold completes and
## frees itself. Then every campaign weather shift: it actually thickens the fog,
## lands inside its hold and is announced, and a "gust" only appears on a level
## that has weather particles to gust (otherwise it is a silent no-op). Live:
## each such level is built and the shift reaches its real Environment and
## particles.
##   godot --headless --path . --audio-driver Dummy res://tests/weather_shift_probe.tscn

var _fails: Array[String] = []

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	await _frames(10)
	var prev_state = GameState.current_state
	GameState.current_state = GameState.State.PLAYING
	await _unit()
	_campaign()
	await _live()
	GameState.current_state = prev_state
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _wait(secs: float) -> void:
	# Short timer loops: one long SceneTreeTimer stalls headless autoload ticks.
	var t := 0.0
	while t < secs:
		await get_tree().create_timer(0.1).timeout
		t += 0.1

func _unit() -> void:
	print("unit:")
	GameState.reset_tasks()
	GameState.register_task("hold", "Hold", 30.0)
	var env := Environment.new()
	env.fog_density = 0.01
	env.fog_light_color = Color(0.2, 0.3, 0.4)
	var snow := CPUParticles3D.new()
	add_child(snow)
	var ws := WeatherShift.new()
	ws.task_id = "hold"
	ws.env = env
	ws.weather = snow
	ws.fog_mult = 4.0
	ws.fade = 0.3
	ws.gust = 2.0
	ws.fog_color = Color(0.8, 0.85, 0.9)
	add_child(ws)
	await _wait(0.6)
	_check(is_equal_approx(env.fog_density, 0.04), "fog thickens by fog_mult (%.4f)" % env.fog_density)
	_check(env.fog_light_color.is_equal_approx(Color(0.8, 0.85, 0.9)), "fog shifts to the authored colour")
	_check(is_equal_approx(snow.speed_scale, 2.0), "the weather particles gust (%.2f)" % snow.speed_scale)
	await _wait(0.4)
	_check(is_equal_approx(env.fog_density, 0.04), "the shift holds while the hold runs")
	GameState.complete_task("hold")
	await _wait(0.8)
	_check(is_equal_approx(env.fog_density, 0.01), "completing the hold eases the fog back (%.4f)" % env.fog_density)
	_check(env.fog_light_color.is_equal_approx(Color(0.2, 0.3, 0.4)), "and its colour")
	_check(is_equal_approx(snow.speed_scale, 1.0), "and the gust")
	_check(not is_instance_valid(ws), "the shift frees itself")
	snow.queue_free()
	GameState.reset_tasks()
	await _frames(3)

func _shifts(def: Dictionary) -> Array:
	var out: Array = []
	for t in def.get("tasks", []):
		if t.get("type", "") != "survive":
			continue
		for w in t.get("waves", []):
			if w.has("weather"):
				out.append({"task": t, "wave": w, "weather": w["weather"]})
	return out

func _campaign() -> void:
	print("campaign:")
	var n := 0
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		for s in _shifts(def):
			n += 1
			var w: Dictionary = s["weather"]
			var hold: float = float(s["task"].get("seconds", 0.0))
			var at: float = float(s["wave"].get("at", 0.0))
			_check(float(w.get("fog_mult", 4.0)) > 1.0, "%s: weather thickens the fog" % id)
			_check(at + float(w.get("fade", 3.0)) + 5.0 <= hold, "%s: weather lands with 5 s of hold left" % id)
			_check(String(w.get("warn_title", "")) != "", "%s: weather shift is announced" % id)
			if float(w.get("gust", 1.0)) != 1.0:
				_check(["snow"].has(String(def.get("env", {}).get("weather", ""))),
					"%s: a gust needs weather particles to gust (env weather '%s')" % [id, def.get("env", {}).get("weather", "")])
	_check(n >= 1, "campaign authors weather shifts (%d)" % n)

func _live() -> void:
	print("live:")
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		var shifts := _shifts(def)
		if shifts.is_empty():
			continue
		var lvl: LevelBuilder = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
		add_child(lvl)
		await _wait(2.5)
		GameState.current_state = GameState.State.PLAYING
		var env: Environment = lvl._env
		var fog0 := env.fog_density
		var w: Dictionary = (shifts[0]["weather"] as Dictionary).duplicate()
		w["fade"] = 0.3
		lvl._start_weather(w, "weather_probe_never_done")
		await _wait(0.6)
		var ws := lvl.get_node_or_null("WeatherShift") as WeatherShift
		_check(ws != null, "%s live: the shift is built" % id)
		_check(env.fog_density > fog0 * 1.5, "%s live: the level's own fog thickens (%.4f -> %.4f)" % [id, fog0, env.fog_density])
		if float(w.get("gust", 1.0)) != 1.0:
			_check(ws != null and is_instance_valid(ws.weather), "%s live: the shift found the level's weather particles" % id)
		lvl.queue_free()
		await _frames(3)
