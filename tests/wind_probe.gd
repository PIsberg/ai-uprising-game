extends Node3D
## Crosswinds (WindZone, def key `wind`) with the REAL player scene on a
## 2.6 m deck 1.6 m up:
##   - the cycle runs CALM -> WARN -> GUST; the windsocks droop when calm and
##     stand out in a gust;
##   - standing still through a gust blows the player off the deck;
##   - crouching braces (stays on, under 1.3 m of drift);
##   - leaning into it (walking upwind) makes headway;
##   - outside the box nothing pushes; the first entry teaches.
## Campaign: every zone's centre is on a walkway, its wind blows ACROSS the
## walkway, and just past the downwind edge is a hazard bed, not a deck.
##   godot --headless --path . --audio-driver Dummy res://tests/wind_probe.tscn

var _fails: Array[String] = []
var _hints: Array[String] = []
var _player: CharacterBody3D
var _zone: WindZone

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _seconds(s: float) -> void:
	await _frames(int(ceil(s * Engine.physics_ticks_per_second)))

func _box(at: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = at
	add_child(sb)

## Waits until the zone enters `ph`.
func _until(ph: WindZone.Phase) -> void:
	while _zone.phase != ph:
		await get_tree().physics_frame

func _sock_y() -> float:
	return (-(_zone._socks[0].global_transform.basis.z)).normalized().y

func _reset() -> void:
	_player.global_position = Vector3(0, 1.75, 0)
	_player.velocity = Vector3.ZERO
	await _frames(10)

func _run() -> void:
	GameState.teach_hint.connect(func(t: String) -> void: _hints.append(t))
	var prev_state = GameState.current_state
	GameState.current_state = GameState.State.PLAYING
	_box(Vector3(0, -0.5, 0), Vector3(80, 1, 80))       # the "water" floor far below
	_box(Vector3(0, 1.4, 0), Vector3(2.6, 0.4, 12))     # the deck, top at 1.6
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	add_child(_player)
	_player.global_position = Vector3(0, 1.75, 20)        # start outside the box
	var pd := _player.get_node("Damageable") as Damageable
	pd.invulnerable = true
	_zone = WindZone.new()
	_zone.size = Vector2(10, 10)
	_zone.dir = Vector3(1, 0, 0)
	_zone.position = Vector3(0, 1.6, 0)
	add_child(_zone)
	await _frames(10)

	print("outside:")
	await _until(WindZone.Phase.GUST)
	var x0 := _player.global_position.x
	await _seconds(_zone.gust * 0.8)
	_check(absf(_player.global_position.x - x0) < 0.05, "outside the box a gust does nothing")
	_hints.clear()

	print("cycle:")
	await _reset()
	_check(_hints.has(WindZone.TEACH_TEXT), "stepping in teaches the rule")
	await _until(WindZone.Phase.CALM)
	await _seconds(0.3)
	var calm_y := _sock_y()
	await _until(WindZone.Phase.WARN)
	await _until(WindZone.Phase.GUST)
	await _seconds(0.2)
	var gust_y := _sock_y()
	_check(calm_y < -0.6 and absf(gust_y) < 0.2, "windsocks droop when calm (%.2f), stand out in a gust (%.2f)" % [calm_y, gust_y])

	print("passive:")
	await _until(WindZone.Phase.CALM)
	await _reset()
	await _until(WindZone.Phase.GUST)
	x0 = _player.global_position.x
	await _until(WindZone.Phase.CALM)
	await _seconds(0.5)
	_check(_player.global_position.x - x0 > 2.5 and _player.global_position.y < 1.0,
		"standing still, a gust blows you off the deck (drift %.1f m, y %.2f)" % [_player.global_position.x - x0, _player.global_position.y])

	print("brace:")
	await _reset()
	await _until(WindZone.Phase.WARN)
	Input.action_press("crouch")
	await _until(WindZone.Phase.GUST)
	x0 = _player.global_position.x
	await _until(WindZone.Phase.CALM)
	Input.action_release("crouch")
	var drift := _player.global_position.x - x0
	_check(drift < 1.3 and _player.global_position.y > 1.5, "crouched, you brace: %.2f m of drift, still on the deck" % drift)

	print("lean in:")
	await _seconds(0.5)
	await _reset()
	# Press upwind as the gust starts (pressed during the warning, the walk
	# alone left the 10 m box before the gust came: a false pass).
	await _until(WindZone.Phase.GUST)
	x0 = _player.global_position.x
	Input.action_press("move_left") # player faces -Z: left is -X, upwind
	var lean_t := 0.8
	await _seconds(lean_t)
	var lean := _player.global_position.x - x0
	Input.action_release("move_left")
	var walk: float = _player.walk_speed * lean_t
	_check(-lean >= 0.3 and -lean < walk * 0.6 and _zone.contains(_player.global_position),
		"leaning into it makes headway, slowed (%.2f m upwind in %.1f s; %.2f m walking in calm air)" % [-lean, lean_t, walk])

	GameState.current_state = prev_state
	await _campaign()
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _on(xz: Vector2, rects: Array) -> bool:
	for r in rects:
		var c: Vector3 = r["pos"]
		var s: Vector3 = r["size"]
		if absf(xz.x - c.x) <= s.x * 0.5 and absf(xz.y - c.z) <= s.z * 0.5:
			return true
	return false

func _in_bed(xz: Vector2, beds: Array) -> bool:
	for b in beds:
		var c: Vector3 = b["pos"]
		var s: Vector2 = b["size"]
		if absf(xz.x - c.x) <= s.x * 0.5 and absf(xz.y - c.z) <= s.y * 0.5:
			return true
	return false

func _campaign() -> void:
	var found := 0
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		if def.get("wind", []).is_empty():
			continue
		print("level %s:" % id)
		var decks: Array = def.get("platforms", [])
		var beds: Array = def.get("lava", [])
		for w in def["wind"]:
			found += 1
			var c: Vector3 = w["pos"]
			var d2: Vector2 = (w.get("dir", Vector2(1, 0)) as Vector2).normalized()
			var deck: Dictionary = {}
			for r in decks:
				var rc: Vector3 = r["pos"]
				var rs: Vector3 = r["size"]
				if absf(c.x - rc.x) <= rs.x * 0.5 and absf(c.z - rc.z) <= rs.z * 0.5 and absf(rc.y + rs.y * 0.5 - c.y) < 0.3:
					deck = r
			_check(not deck.is_empty(), "%s wind at %s sits on a walkway deck" % [id, c])
			if deck.is_empty():
				continue
			var rs: Vector3 = deck["size"]
			var long_x := rs.x > rs.z
			_check((long_x and absf(d2.y) > 0.9) or (not long_x and absf(d2.x) > 0.9), "%s wind at %s blows across its walkway" % [id, c])
			var half_w := (rs.z if long_x else rs.x) * 0.5
			var past := Vector2(c.x, c.z) + d2 * (half_w + 1.5)
			_check(_in_bed(past, beds) and not _on(past, decks), "%s wind at %s blows you into a hazard, not onto a deck" % [id, c])
	_check(found >= 1, "at least one level has crosswinds (%d)" % found)
