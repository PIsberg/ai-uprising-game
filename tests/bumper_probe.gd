extends Node3D
## Probe: Bumper, the pinball pad that throws whoever steps on it ("bumpers").
## A bumper at the origin aimed at a ring 9 m away:
## (1) a player stepping onto it lands within 1.2 m of its ring, after a real
##     arc (feet 1.5 m up or more), inside the flight time + 1 s;
## (2) a grounded robot on it is thrown too: it leaves the floor, lands within
##     2 m of the ring, is not hurt, and is back under its own AI once down;
## (3) a flyer is never thrown, even brushing the floor over it;
## (4) the ring it throws to is drawn on the floor where the throw lands;
## (5) walking up to one teaches the rule, once;
## (6) the Neon Arcade's bumpers each throw across an energy conduit and land
##     clear of it, of the arcade's cabinets and of its jump pads.
##   godot --headless --path . --audio-driver Dummy res://tests/bumper_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _box(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	add_child(body)
	body.global_position = pos

func _phys(t: float) -> void:
	var tt := 0.0
	while tt < t:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()

## Wait for `body` to be thrown and come down; [landed position, top height, seconds].
func _flight(body: CharacterBody3D, limit: float) -> Array:
	var top := -INF
	var t := 0.0
	var up := false
	while t < limit:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		top = maxf(top, body.global_position.y)
		if body.global_position.y > 0.8:
			up = true
		if up and body.is_on_floor():
			break
	return [body.global_position, top, t]

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_box(Vector3(0, -0.5, 0), Vector3(120, 1, 120))
	var taught: Array[String] = []
	GameState.teach_hint.connect(func(text: String) -> void: taught.append(text))
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(-30, 0.1, -30)
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 100000.0
	php.current_health = 100000.0

	var bp := Bumper.new()
	bp.to = Vector3(0, 0, 9)
	add_child(bp)
	bp.global_position = Vector3.ZERO
	var thrown: Array = []
	bp.bumped.connect(func(b: Node) -> void: thrown.append(b))
	await get_tree().physics_frame
	_check("nothing taught from 40 m off", taught.is_empty(), "(%s)" % [taught])
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var flight: float = JumpPad.solve(Vector3.ZERO, bp.to, JumpPad.apex_for(Vector3.ZERO, bp.to) + Bumper.EXTRA_ARC, g)[1]

	# (4) the ring.
	_check("its landing ring is drawn where it throws", bp.landing_marker().global_position.distance_to(bp.to) < 0.2,
		"(%s vs %s)" % [bp.landing_marker().global_position, bp.to])

	# (1) the player.
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(0, 0.2, 0)
	var r: Array = await _flight(player, flight + 1.0)
	var land: Vector3 = r[0]
	_check("a player is thrown onto its ring", Vector2(land.x - bp.to.x, land.z - bp.to.z).length() < 1.2,
		"(lands %s, ring %s)" % [land, bp.to])
	_check("on a real arc", float(r[1]) >= 1.5, "(feet top %.2f m)" % float(r[1]))
	_check("in time", float(r[2]) <= flight + 1.0, "(%.2f s, flight %.2f s)" % [float(r[2]), flight])
	_check("walking up to it teaches the rule, once", taught.count(Bumper.TEACH_TEXT) == 1, "(%s)" % [taught])
	player.global_position = Vector3(-30, 0.1, -30)
	await _phys(1.0)

	# (2) a grounded robot.
	var bot: EnemyBase = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	bot.position = Vector3(0, 0.0, 20.0) # placed before it enters the tree: not on the pad
	add_child(bot)
	bot.set("move_speed", 0.0)
	# Stock health: inflating it would make the chassis count as a boss, which
	# a bumper (rightly) refuses to throw.
	var hurt := [0]
	bot.hp.damaged.connect(func(_a: float, _src) -> void: hurt[0] += 1)
	await _phys(0.6) # settle on the floor clear of the pad
	bot.global_position = Vector3(0, 0.05, 0)
	var rb: Array = await _flight(bot, flight + 1.5)
	var bl: Vector3 = rb[0]
	_check("a grounded robot is thrown too", thrown.has(bot) and float(rb[1]) > 1.0, "(feet top %.2f m)" % float(rb[1]))
	_check("and lands on the ring", Vector2(bl.x - bp.to.x, bl.z - bp.to.z).length() < 2.0, "(lands %s)" % bl)
	_check("unhurt", hurt[0] == 0, "(%d hits)" % hurt[0])
	await _phys(0.3)
	_check("back under its own AI once down", not bot.is_launched())
	bot.queue_free()

	# (3) a flyer hovering over it.
	var drone: EnemyBase = (load("res://scenes/enemies/drone.tscn") as PackedScene).instantiate()
	drone.position = Vector3(0, 0.4, 0) # low enough to brush the floor over the pad
	add_child(drone)
	await _phys(1.0)
	_check("a flyer is not thrown", not thrown.has(drone))
	drone.queue_free()
	bp.queue_free()

	_neon()
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

func _in_rect(p: Vector3, c: Vector3, size: Vector2, pad: float) -> bool:
	return absf(p.x - c.x) <= size.x * 0.5 + pad and absf(p.z - c.z) <= size.y * 0.5 + pad

func _neon() -> void:
	var def := LevelDefs.get_def("neon")
	var bumpers: Array = def.get("bumpers", [])
	_check("neon has bumpers", bumpers.size() >= 2, "(%d)" % bumpers.size())
	for b in bumpers:
		var p: Vector3 = b["pos"]
		var to: Vector3 = b["to"]
		var crosses := false
		var clear := true
		var why := ""
		for l in def.get("lava", []):
			var c: Vector3 = l["pos"]
			var sz: Vector2 = l["size"]
			for k in 21:
				if _in_rect(p.lerp(to, k / 20.0), c, sz, 0.0):
					crosses = true
			if _in_rect(to, c, sz, 1.0) or _in_rect(p, c, sz, 1.0):
				clear = false
				why = "conduit at %s" % c
		for w in def.get("walls", []):
			var c: Vector3 = w["pos"]
			var s3: Vector3 = w["size"]
			if _in_rect(to, c, Vector2(s3.x, s3.z), 1.2) or _in_rect(p, c, Vector2(s3.x, s3.z), 1.2):
				clear = false
				why = "cabinet at %s" % c
		for j in def.get("jump_pads", []):
			var jp: Vector3 = j["pos"]
			if Vector2(jp.x - to.x, jp.z - to.z).length() < 3.0 or Vector2(jp.x - p.x, jp.z - p.z).length() < 3.0:
				clear = false
				why = "jump pad at %s" % jp
		_check("bumper at %s throws across a conduit" % p, crosses)
		_check("and it and its ring stand clear of conduits, cabinets and pads", clear, why)
