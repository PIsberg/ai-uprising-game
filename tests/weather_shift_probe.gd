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
	await _unit_blackout()
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

## A blackout hides every "level_light" (lights and lit fixture panels) and
## scales the ambient; completing the task brings back exactly what it hid.
func _unit_blackout() -> void:
	print("unit blackout:")
	GameState.reset_tasks()
	GameState.register_task("dark", "Dark", 0.0)
	var env := Environment.new()
	env.ambient_light_energy = 1.0
	env.tonemap_exposure = 1.0
	var lamp := OmniLight3D.new()
	var panel := MeshInstance3D.new()
	var off := OmniLight3D.new() # already off before the cut: must stay off after
	off.visible = false
	for n in [lamp, panel, off]:
		n.add_to_group("level_light")
		add_child(n)
	var ws := WeatherShift.new()
	ws.task_id = "dark"
	ws.env = env
	ws.fog_mult = 1.0
	ws.fade = 0.3
	ws.blackout = true
	ws.ambient_mult = 0.4
	ws.exposure_mult = 0.5
	add_child(ws)
	await _wait(0.6)
	_check(not lamp.visible and not panel.visible, "the blackout cuts lights and lit panels")
	_check(is_equal_approx(env.ambient_light_energy, 0.4), "and dims the ambient (%.2f)" % env.ambient_light_energy)
	_check(is_equal_approx(env.tonemap_exposure, 0.5), "and the exposure (%.2f)" % env.tonemap_exposure)
	GameState.complete_task("dark")
	await _wait(0.8)
	_check(lamp.visible and panel.visible, "power comes back when the task completes")
	_check(not off.visible, "a light that was already off stays off")
	_check(is_equal_approx(env.ambient_light_energy, 1.0), "and the ambient is restored (%.2f)" % env.ambient_light_energy)
	_check(is_equal_approx(env.tonemap_exposure, 1.0), "and the exposure (%.2f)" % env.tonemap_exposure)
	for n in [lamp, panel, off]:
		n.queue_free()
	GameState.reset_tasks()
	await _frames(3)

## Every weather shift a level authors: on a survive wave (lands mid-hold) or on
## a task itself (runs while that stage is live; "wave" is empty).
func _shifts(def: Dictionary) -> Array:
	var out: Array = []
	for t in def.get("tasks", []):
		if t.has("weather"):
			out.append({"task": t, "wave": {}, "weather": t["weather"]})
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
			_check(float(w.get("fog_mult", 4.0)) > 1.0 or bool(w.get("blackout", false)) or float(w.get("ambient_mult", 1.0)) < 1.0,
				"%s: the weather shift changes something (fog, blackout or ambient)" % id)
			if not (s["wave"] as Dictionary).is_empty():
				_check(at + float(w.get("fade", 3.0)) + 5.0 <= hold, "%s: weather lands with 5 s of hold left" % id)
			_check(String(w.get("warn_title", "")) != "", "%s: weather shift is announced" % id)
			if float(w.get("gust", 1.0)) != 1.0:
				var lvl_w := String(def.get("env", {}).get("weather", ""))
				var raised := String(w.get("particles", ""))
				_check(["snow", "dust", "rain"].has(lvl_w) or ["snow", "dust", "rain"].has(raised),
					"%s: a gust needs weather particles to gust (env weather '%s', raised '%s')" % [id, lvl_w, raised])
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
		if float(w.get("fog_mult", 4.0)) > 1.0:
			_check(env.fog_density > fog0 * 1.5, "%s live: the level's own fog thickens (%.4f -> %.4f)" % [id, fog0, env.fog_density])
		if bool(w.get("blackout", false)):
			var lit := get_tree().get_nodes_in_group("level_light").filter(func(n): return (n as Node3D).visible)
			_check(ws != null and ws._dark.size() > 0 and lit.is_empty(),
				"%s live: the blackout cut the level's %d lights and panels" % [id, ws._dark.size() if ws else 0])
		if float(w.get("gust", 1.0)) != 1.0:
			_check(ws != null and is_instance_valid(ws.weather), "%s live: the shift found the level's weather particles" % id)
		if w.has("particles") and String(def.get("env", {}).get("weather", "")) == "":
			# Raised for the storm: owned, and gone once the hold is won.
			var raised: Node = ws.weather if ws != null else null
			_check(ws != null and ws.owns_weather, "%s live: the storm raised its own particles" % id)
			ws.task_id = "weather_probe_done"
			GameState.register_task("weather_probe_done", "x", 0.0)
			GameState.complete_task("weather_probe_done")
			await _wait(float(raised.get("lifetime")) + 0.3 + 1.0 if is_instance_valid(raised) else 0.5)
			_check(not is_instance_valid(raised), "%s live: the raised particles are freed after the storm" % id)
		lvl.queue_free()
		await _frames(3)
