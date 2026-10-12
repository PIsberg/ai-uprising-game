extends Node3D
## Probe: JumpPad, the launch pad ("jump_pads" def key).
## (1) a player stepping onto a pad (no input held) lands on its target deck:
##     feet within 0.3 m of the deck's height and within 1.2 m of the target
##     on the ground plane, inside the flight time + 1 s;
## (2) a pad with a height cap (`max_apex`, the indoor ceiling) keeps the
##     player's feet under it the whole flight, and still lands on target;
## (3) robots are not launched;
## (4) NEON ARCADE's pads each land on a deck (a platform or the tower roof)
##     and every arc clears the room's ceiling with head room (feet apex +
##     1.9 m under it);
## (5) in the built NEON level, a ride from each pad lands on its target
##     (nothing in the way: railings, pillars, the ceiling).
##   godot --headless --path . --audio-driver Dummy res://tests/jump_pad_probe.tscn

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

## Step `player` onto `pad`; returns [landing position, highest feet y, time].
func _ride(player: CharacterBody3D, pad: JumpPad, target: Vector3) -> Array:
	player.velocity = Vector3.ZERO
	player.global_position = pad.global_position + Vector3.UP * 0.2
	var top := -INF
	var t := 0.0
	var launched := false
	while t < 5.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		top = maxf(top, player.global_position.y)
		if player.global_position.y > pad.global_position.y + 0.8:
			launched = true
		if launched and player.is_on_floor() and player.global_position.distance_to(target) < 3.0:
			break
	return [player.global_position, top, t]

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_box(Vector3(0, -0.5, 0), Vector3(120, 1, 120))
	_box(Vector3(0, 3.8, 12), Vector3(5, 0.4, 5))      # deck A, top 4.0
	_box(Vector3(20, 1.8, 0), Vector3(5, 0.4, 5))      # deck B, top 2.0
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(-20, 0.2, -20)
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 100000.0
	php.current_health = 100000.0

	var a := JumpPad.new()
	a.to = Vector3(0, 4.0, 12)
	add_child(a)
	a.global_position = Vector3(0, 0, 0)
	var ra: Array = await _ride(player, a, a.to)
	var la: Vector3 = ra[0]
	print("  pad A: landed %s after %.2f s, apex %.2f" % [la, ra[2], ra[1]])
	_check("pad A lands on its deck", absf(la.y - 4.0) < 0.3 and Vector2(la.x - a.to.x, la.z - a.to.z).length() < 1.2, "(%s)" % la)

	var b := JumpPad.new()
	b.to = Vector3(20, 2.0, 0)
	b.max_apex = 4.0
	add_child(b)
	b.global_position = Vector3(0, 0, -10)
	var rb: Array = await _ride(player, b, b.to)
	var lb: Vector3 = rb[0]
	print("  pad B: landed %s after %.2f s, apex %.2f (cap 4.0)" % [lb, rb[2], rb[1]])
	_check("capped pad lands on its deck", absf(lb.y - 2.0) < 0.3 and Vector2(lb.x - b.to.x, lb.z - b.to.z).length() < 1.2, "(%s)" % lb)
	_check("capped arc stays under its cap", float(rb[1]) <= 4.0 + 0.2, "(apex %.2f)" % rb[1])

	# A robot walking over a pad stays on the ground.
	var e: CharacterBody3D = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	add_child(e)
	e.global_position = a.global_position + Vector3.UP * 0.2
	var hi := 0.0
	var t := 0.0
	while t < 1.5:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		hi = maxf(hi, e.global_position.y)
	_check("robots are not launched", hi < 1.0, "(rose to %.2f)" % hi)

	# NEON ARCADE.
	var def := LevelDefs.get_def("neon")
	var pads: Array = def.get("jump_pads", [])
	_check("neon has jump pads", pads.size() >= 2, "(%d)" % pads.size())
	var ceiling := 6.0
	for tw in def.get("towers", []):
		ceiling = maxf(ceiling, float(tw.get("height", 8.0)) + 2.5)
	for p in pads:
		var to: Vector3 = p["to"]
		var on_deck := false
		for pl in def.get("platforms", []):
			var c: Vector3 = pl["pos"]
			var s: Vector3 = pl["size"]
			if absf(to.x - c.x) < s.x * 0.5 - 0.5 and absf(to.z - c.z) < s.z * 0.5 - 0.5 and absf(to.y - (c.y + s.y * 0.5)) < 0.3:
				on_deck = true
		for tw in def.get("towers", []):
			var tp: Vector3 = tw["pos"]
			if Vector2(to.x - tp.x, to.z - tp.z).length() < float(tw.get("radius", 3.0)) - 0.6 and absf(to.y - (float(tw["height"]) + 0.2)) < 0.4:
				on_deck = true
		_check("pad to %s lands on a deck" % to, on_deck)
		var apex := JumpPad.apex_for(p["pos"], to, float(p.get("max_apex", ceiling - 2.0)))
		_check("pad to %s clears the ceiling" % to, apex + 1.9 <= ceiling, "(feet apex %.2f, ceiling %.2f)" % [apex, ceiling])
	await _live_neon(player)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()

func _live_neon(test_player: Node) -> void:
	test_player.queue_free()
	for c in get_children():
		if c is StaticBody3D or c is JumpPad or c is EnemyBase:
			c.queue_free()
	await get_tree().physics_frame
	var lvl: Node3D = (load("res://scenes/levels/level_neon.tscn") as PackedScene).instantiate()
	add_child(lvl)
	for i in 20:
		await get_tree().physics_frame
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	var hp: Node = player.get_node("Damageable")
	hp.set("invulnerable", true)
	for pad in lvl.find_children("*", "JumpPad", true, false):
		var jp := pad as JumpPad
		var r: Array = await _ride(player, jp, jp.to)
		var land: Vector3 = r[0]
		print("  neon pad -> %s: landed %s after %.2f s" % [jp.to, land, r[2]])
		_check("neon ride lands on %s" % jp.to, absf(land.y - jp.to.y) < 0.4 and Vector2(land.x - jp.to.x, land.z - jp.to.z).length() < 1.5, "(%s)" % land)
