extends Node3D
## Probe: PendulumBlade, the swinging blade on a walkway gantry ("pendulums").
## A gantry 4 m wide across a path along z, at the origin:
## (1) the blade sweeps the whole walkway at standing height: every spot
##     across it is reached at some point of a swing (no safe lane);
## (2) a player standing in the cut is hit, and thrown along the path;
## (3) a careful player who waits 1.5 m short of the cut and walks through
##     (4 m/s) whenever the sign reads GO is never hit, at five spots across
##     the walkway, arriving at four points of the swing at each; one who walks through at evenly spread times regardless of
##     the sign is hit at least once;
## (4) the sign reads WAIT at some point of every swing at the centre line,
##     and GO at some point;
## (5) walking up to it teaches the rule, once;
## (6) LAVA WORLD's gantries straddle a walkway: centred on its line, posts
##     outside its (scaled) width, the path along its length.
##   godot --headless --path . --audio-driver Dummy res://tests/pendulum_blade_probe.tscn

var ok := true
var _hits := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)

func _phys(t: float) -> void:
	var tt := 0.0
	while tt < t:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()

## Walk `player` along +z from z = -1.5 to +1.5 at 4 m/s at `x`; hits taken.
func _walk(player: CharacterBody3D, x: float) -> int:
	var before := _hits
	var z := -1.5
	while z < 1.5:
		player.global_position = Vector3(x, 0, z)
		await get_tree().physics_frame
		z += 4.0 * get_physics_process_delta_time()
	return _hits - before

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_floor()
	var taught: Array[String] = []
	GameState.teach_hint.connect(func(text: String) -> void: taught.append(text))
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0, 30)
	player.set_physics_process(false)
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	php.damaged.connect(func(_a: float, src: Node) -> void:
		if src is PendulumBlade:
			_hits += 1)

	var pb := PendulumBlade.new()
	pb.width = 4.0
	pb.path_axis = "z"
	add_child(pb)
	pb.global_position = Vector3.ZERO

	# (1) no safe lane across the walkway.
	var lane_ok := true
	var worst := ""
	for i in 9:
		var x := lerpf(-pb.width * 0.5 + 0.35, pb.width * 0.5 - 0.35, i / 8.0)
		var reached := false
		var a := -pb.amplitude
		while a <= pb.amplitude:
			reached = reached or pb.reaches(a, x, 0.0, 1.8)
			a += 1.0
		if not reached:
			lane_ok = false
			worst = "x %.2f never reached" % x
	_check("the blade sweeps the whole walkway at standing height", lane_ok, worst)

	# (4) the sign at the centre line over two swings.
	var saw_go := false
	var saw_wait := false
	var t := 0.0
	while t < pb.period * 2.0:
		await _phys(0.05)
		t += 0.05
		saw_go = saw_go or pb.sign_text() == "GO"
		saw_wait = saw_wait or pb.sign_text() == "WAIT"
	_check("the sign reads GO and WAIT within a swing", saw_go and saw_wait)
	_check("nothing taught from 30 m off", taught.is_empty(), "(%s)" % [taught])

	# (2) standing in the cut.
	player.global_position = Vector3(0, 0, 0.1)
	_hits = 0
	await _phys(pb.period)
	_check("a player standing in the cut is hit", _hits >= 1, "(%d)" % _hits)
	_check("walking up to it teaches the rule, once", taught.count(PendulumBlade.TEACH_TEXT) == 1, "(%s)" % [taught])
	player.global_position = Vector3(0, 0, 0.1)
	player.velocity = Vector3.ZERO
	pb.set("_cool", 0.0)
	var shoved := false
	for i in 120:
		await get_tree().physics_frame
		player.global_position = Vector3(0, 0, 0.1)
		if absf(player.velocity.z) > 4.0:
			shoved = true
			break
	_check("a hit throws the player along the path", shoved, "(%s)" % player.velocity)

	# (3) careful crossings on GO, at five spots, arriving at four points of
	# the swing each: a player who turns up late in a GO window must still be
	# safe, which is what the sign's lookahead is for.
	var careful_hits := 0
	var crossings := 0
	for i in 5:
		var x := lerpf(-1.4, 1.4, i / 4.0)
		for j in 4:
			player.global_position = Vector3(x, 0, -1.5)
			pb.set("_cool", 0.0)
			await _phys(pb.period * (0.25 * j + 0.13))
			var guard := 0
			while pb.sign_text() != "GO" and guard < 400:
				await get_tree().physics_frame
				player.global_position = Vector3(x, 0, -1.5)
				guard += 1
			careful_hits += await _walk(player, x)
			crossings += 1
	_check("crossing on GO is never hit (5 spots x 4 arrivals)", careful_hits == 0, "(%d hits in %d crossings)" % [careful_hits, crossings])
	var clumsy_hits := 0
	for i in 8:
		player.global_position = Vector3(0, 0, -1.5)
		pb.set("_cool", 0.0)
		await _phys(pb.period / 8.0 * 3.0)
		clumsy_hits += await _walk(player, 0.0)
	_check("crossing regardless of the sign gets hit", clumsy_hits >= 1, "(%d of 8)" % clumsy_hits)
	pb.queue_free()

	_forge()
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

func _forge() -> void:
	var def := LevelDefs.get_def("lava_world")
	var gantries: Array = def.get("pendulums", [])
	_check("lava_world has pendulum gantries", gantries.size() >= 2, "(%d)" % gantries.size())
	for g in gantries:
		var p: Vector3 = g["pos"]
		var along_z := String(g.get("path", "z")) == "z"
		var on: Dictionary = {}
		for pl in def.get("platforms", []):
			var c: Vector3 = pl["pos"]
			var sz: Vector3 = pl["size"]
			var long_z := sz.z > sz.x
			if long_z != along_z:
				continue
			if absf(p.x - c.x) <= sz.x * 0.5 and absf(p.z - c.z) <= sz.z * 0.5 and absf(c.y + sz.y * 0.5 - p.y) < 0.05:
				on = pl
		_check("gantry at %s straddles a walkway along its path" % p, not on.is_empty())
		if on.is_empty():
			continue
		var c: Vector3 = on["pos"]
		var sz: Vector3 = on["size"]
		var off := absf(p.x - c.x) if along_z else absf(p.z - c.z)
		var half := (sz.x if along_z else sz.z) * 0.5
		_check("centred on the walkway's line", off < 0.05, "(%.2f m off)" % off)
		_check("posts outside the walkway", float(g["width"]) * 0.5 > half, "(%.2f vs %.2f)" % [float(g["width"]) * 0.5, half])
