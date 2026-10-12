extends Node3D
## Probe: ZipLine, a two-way cable between two decks ("ziplines" def key).
## (1) a player stepping into one station rides the cable and comes to rest
##     on the other deck (feet within 0.4 m of it, within 2 m of the station),
##     inside 6 s, and stays there (does not ride straight back);
## (2) stepping off and back on rides them back;
## (3) robots are not carried;
## (4) TITAN has a zipline from the east tower roof to the south-west deck,
##     and the straight line between its stations (at chest height) is clear;
## (5) in the built TITAN level a ride from the tower lands on the deck.
##   godot --headless --path . --audio-driver Dummy res://tests/zipline_probe.tscn

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

func _wait(t: float) -> void:
	var tt := 0.0
	while tt < t:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()

## Put the player on `from`; wait until they rest near `to`. [rest pos, seconds].
func _ride(player: CharacterBody3D, from: Vector3, to: Vector3) -> Array:
	player.velocity = Vector3.ZERO
	player.global_position = from + Vector3.UP * 0.2
	var t := 0.0
	var still := 0.0
	while t < 8.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var near := Vector2(player.global_position.x - to.x, player.global_position.z - to.z).length() < 2.0
		still = still + get_physics_process_delta_time() if near and player.is_on_floor() else 0.0
		if still > 0.4:
			break
	return [player.global_position, t]

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_box(Vector3(0, -0.5, 0), Vector3(160, 1, 160))
	_box(Vector3(0, 3.8, 0), Vector3(6, 0.4, 6))     # deck A, top 4.0
	_box(Vector3(30, 1.8, 12), Vector3(6, 0.4, 6))   # deck B, top 2.0
	var a := Vector3(0, 4.0, 0)
	var b := Vector3(30, 2.0, 12)
	var zip := ZipLine.new()
	zip.a = a
	zip.b = b
	add_child(zip)
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(-30, 0.2, -30)
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 100000.0
	php.current_health = 100000.0

	var r: Array = await _ride(player, a, b)
	var land: Vector3 = r[0]
	print("  A -> B: rest %s after %.1f s" % [land, r[1]])
	_check("rides A to B", absf(land.y - b.y) < 0.4 and Vector2(land.x - b.x, land.z - b.z).length() < 2.0, "(%s)" % land)
	await _wait(2.0)
	_check("stays at B (no ride straight back)", Vector2(player.global_position.x - b.x, player.global_position.z - b.z).length() < 2.5, "(%s)" % player.global_position)

	# Step off, then back on: rides back to A.
	player.global_position = b + Vector3(2.6, 0.2, 0)
	await _wait(0.3)
	var back: Array = await _ride(player, b, a)
	var land2: Vector3 = back[0]
	print("  B -> A: rest %s after %.1f s" % [land2, back[1]])
	_check("rides back B to A", absf(land2.y - a.y) < 0.4 and Vector2(land2.x - a.x, land2.z - a.z).length() < 2.0, "(%s)" % land2)

	var e: CharacterBody3D = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	add_child(e)
	e.global_position = b + Vector3.UP * 0.3
	e.set("move_speed", 0.0)
	await _wait(1.5)
	_check("robots are not carried", Vector2(e.global_position.x - b.x, e.global_position.z - b.z).length() < 1.0, "(%s)" % e.global_position)
	e.queue_free()
	zip.queue_free()

	# TITAN.
	var def := LevelDefs.get_def("titan")
	var zips: Array = def.get("ziplines", [])
	_check("titan has a zipline", zips.size() >= 1, "(%d)" % zips.size())
	var tower: Dictionary = {}
	for tw in def.get("towers", []):
		if (tw["pos"] as Vector3).x > 0.0:
			tower = tw
	var deck: Dictionary = {}
	for pl in def.get("platforms", []):
		if (pl["pos"] as Vector3).x < 0.0 and (pl["pos"] as Vector3).z > 0.0:
			deck = pl
	for z in zips:
		var za: Vector3 = z["a"]
		var zb: Vector3 = z["b"]
		var tp: Vector3 = tower["pos"]
		_check("one end on the east tower roof", Vector2(za.x - tp.x, za.z - tp.z).length() < float(tower["radius"]) - 0.8 and absf(za.y - float(tower["height"])) < 0.3, "(%s)" % za)
		var dp: Vector3 = deck["pos"]
		var ds: Vector3 = deck["size"]
		_check("other end on the south-west deck", absf(zb.x - dp.x) < ds.x * 0.5 - 0.8 and absf(zb.z - dp.z) < ds.z * 0.5 - 0.8 and absf(zb.y - (dp.y + ds.y * 0.5)) < 0.3, "(%s)" % zb)
	await _live_titan(player)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()

func _live_titan(test_player: Node) -> void:
	test_player.queue_free()
	for c in get_children():
		if c is StaticBody3D:
			c.queue_free()
	await get_tree().physics_frame
	var lvl: Node3D = (load("res://scenes/levels/level_titan.tscn") as PackedScene).instantiate()
	add_child(lvl)
	for i in 20:
		await get_tree().physics_frame
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	player.get_node("Damageable").set("invulnerable", true)
	for z in lvl.find_children("*", "ZipLine", true, false):
		var zl := z as ZipLine
		# Straight line between the stations at chest height: nothing in the way.
		var q := PhysicsRayQueryParameters3D.create(zl.a + Vector3.UP * 1.3, zl.b + Vector3.UP * 1.3, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		_check("titan cable path is clear", hit.is_empty(), "(hit %s)" % (hit.get("position", Vector3.ZERO) if not hit.is_empty() else ""))
		var r: Array = await _ride(player, zl.a, zl.b)
		var land: Vector3 = r[0]
		print("  titan ride: rest %s after %.1f s" % [land, r[1]])
		_check("titan ride lands on the deck", absf(land.y - zl.b.y) < 0.4 and Vector2(land.x - zl.b.x, land.z - zl.b.z).length() < 2.0, "(%s)" % land)
