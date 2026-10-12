extends Node3D
## Probe: ShockFloor, the electrified tile floor ("shock_floors" def key).
## A 4 x 2 checker of 2 m tiles at the origin, over two full cycles:
## (1) the two groups take turns, and every arc on a group comes WARN_TIME
##     (0.9 s) after its glow starts;
## (2) in a checker every tile's four neighbours are in the other group, so a
##     glowing tile always has a dark one next to it;
## (3) a player on a tile is hit only while that tile arcs, never while it
##     glows; with their feet 0.6 m up (mid-jump) never; off the floor never;
## (4) a robot on an arcing tile is not hurt;
## (5) walking up to it teaches the rule, once;
## (6) the Neon Arcade's floor spans the inside of its north gap, one row
##     deep at least, and nothing a level needs (task zones, pads) sits on it.
##   godot --headless --path . --audio-driver Dummy res://tests/shock_floor_probe.tscn

var ok := true
var _clock := 0.0

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
		_clock += get_physics_process_delta_time()

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

	var sf := ShockFloor.new()
	sf.cells = Vector2i(4, 2)
	sf.cell = 2.0
	add_child(sf)
	sf.global_position = Vector3.ZERO
	var cycle := (ShockFloor.WARN_TIME + ShockFloor.ZAP_TIME) * sf.group_count()

	# (1) turns and warning lead, from 30 m off.
	var warn_at := {}
	var leads: Array[float] = []
	var groups: Array[int] = []
	sf.warning.connect(func(g: int) -> void:
		warn_at[g] = _clock
		groups.append(g))
	sf.zapped.connect(func(g: int) -> void:
		leads.append(_clock - float(warn_at.get(g, -100.0))))
	await _phys(cycle * 2.0)
	_check("the groups take turns", groups.size() >= 4 and groups[0] != groups[1] and groups[1] != groups[2], "(%s)" % [groups])
	var lead_ok := leads.size() >= 3
	for l in leads:
		lead_ok = lead_ok and absf(l - ShockFloor.WARN_TIME) < 0.05
	_check("every arc comes 0.9 s after its glow", lead_ok, "(leads %s)" % [leads])
	_check("nothing taught from 30 m off", taught.is_empty(), "(%s)" % [taught])

	# (2) a dark neighbour for every tile.
	var neighbours_ok := true
	for iz in sf.cells.y:
		for ix in sf.cells.x:
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(ix, iz) + d
				if n.x < 0 or n.y < 0 or n.x >= sf.cells.x or n.y >= sf.cells.y:
					continue
				neighbours_ok = neighbours_ok and sf.group_of(n.x, n.y) != sf.group_of(ix, iz)
	_check("every tile's neighbours are in the other group", neighbours_ok)

	# (3) on tile (1, 0): hit only while it arcs.
	var tile := Vector2i(1, 0)
	var at := sf.tile_center(tile.x, tile.y)
	var hit_states: Array[int] = []
	php.damaged.connect(func(_a: float, src: Node) -> void:
		if src is ShockFloor:
			hit_states.append(sf.tile_state(tile.x, tile.y)))
	player.global_position = at
	await _phys(cycle * 2.0)
	var only_zap := hit_states.size() >= 4
	for s in hit_states:
		only_zap = only_zap and s == ShockFloor.Tile.ZAP
	_check("on a tile: hit only while it arcs", only_zap, "(%d hits, states %s)" % [hit_states.size(), hit_states])
	_check("walking up to it teaches the rule, once", taught.count(ShockFloor.TEACH_TEXT) == 1, "(%s)" % [taught])
	hit_states.clear()
	player.global_position = at + Vector3.UP * 0.6
	await _phys(cycle * 2.0)
	_check("mid-jump: never hit", hit_states.is_empty(), "(%d)" % hit_states.size())
	player.global_position = Vector3(0, 0, sf.cells.y * sf.cell * 0.5 + 0.4)
	await _phys(cycle * 2.0)
	_check("off the floor: never hit", hit_states.is_empty(), "(%d)" % hit_states.size())

	# (4) robots.
	player.global_position = Vector3(0, 0, 30)
	var bot: EnemyBase = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	add_child(bot)
	bot.global_position = at
	bot.process_mode = Node.PROCESS_MODE_DISABLED # frozen on the tile (live robots drift)
	var bot_hits := [0]
	bot.hp.damaged.connect(func(_a: float, src: Node) -> void:
		if src is ShockFloor:
			bot_hits[0] += 1)
	await _phys(cycle * 2.0)
	_check("a robot on an arcing tile is not hurt", bot_hits[0] == 0, "(%d)" % bot_hits[0])
	sf.queue_free()

	_neon()
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

func _neon() -> void:
	var def := LevelDefs.get_def("neon")
	var floors: Array = def.get("shock_floors", [])
	_check("neon has a shock floor", floors.size() >= 1, "(%d)" % floors.size())
	if floors.is_empty():
		return
	var f: Dictionary = floors[0]
	var c: Vector3 = f["pos"]
	var n: Vector2i = f["cells"]
	var sz := float(f["cell"])
	var x0 := c.x - n.x * sz * 0.5
	var x1 := c.x + n.x * sz * 0.5
	var z0 := c.z - n.y * sz * 0.5
	var z1 := c.z + n.y * sz * 0.5
	var gate: Dictionary = {}
	for g in def.get("gates", []):
		if String(g["axis"]) == "z":
			gate = g
	var lo := float(gate["gap_pos"]) - float(gate["gap"]) * 0.5
	var hi := float(gate["gap_pos"]) + float(gate["gap"]) * 0.5
	var face := float(gate["at"]) + 0.5 # the inner face of the 1 m bulkhead
	_check("it spans the north gap", x0 <= lo + 0.01 and x1 >= hi - 0.01, "(%.1f..%.1f vs gap %.1f..%.1f)" % [x0, x1, lo, hi])
	_check("it starts at the bulkhead's inner face", absf(z0 - face) < 0.5, "(%.2f vs %.2f)" % [z0, face])
	_check("it is at least one tile deep past the gap", z1 - z0 >= sz - 0.01)
	var clear := true
	var what := ""
	for t in def.get("tasks", []):
		if t.has("pos"):
			var p: Vector3 = t["pos"]
			if p.x > x0 - 2.0 and p.x < x1 + 2.0 and p.z > z0 - 2.0 and p.z < z1 + 2.0:
				clear = false
				what = "task %s" % p
	for jp in def.get("jump_pads", []):
		var p: Vector3 = jp["pos"]
		if p.x > x0 - 1.5 and p.x < x1 + 1.5 and p.z > z0 - 1.5 and p.z < z1 + 1.5:
			clear = false
			what = "pad %s" % p
	_check("no task zone or pad sits on it", clear, what)
