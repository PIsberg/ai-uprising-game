extends Node3D
## Probe: CargoLift, the ridable lift ("lifts" def key).
## (1) a player standing on the car at the bottom is carried up: within
##     travel time + 2 s they stand at the top landing (feet within 0.3 m of
##     it), and never drop through the car on the way;
## (2) stepping off at the top and standing by the bottom landing calls the
##     empty car back down within travel time + 2 s;
## (3) the car's top surface is solid ground at both ends (a ray down from
##     above its centre hits it within 0.05 m of the landing height);
## (4) LAVA WORLD and WATER WORLD each have a lift whose top lands flush
##     (within 0.15 m) beside a deck that nothing else reaches, and whose
##     bottom is flush with the island it stands on;
## (5) a lift's top landing stays dry: at least 1 m above the highest flood
##     any task on its level raises (WATER WORLD's tide surge).
##   godot --headless --path . --audio-driver Dummy res://tests/cargo_lift_probe.tscn

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

func _ray_y(at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 12.0, at + Vector3.DOWN * 12.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3).y if hit else -INF

func _wait(t: float) -> void:
	var tt := 0.0
	while tt < t:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))             # floor, top at 0
	_box(Vector3(-4.0, 6.8, 0), Vector3(4, 0.4, 4))           # top deck, surface 7.0, west of the shaft
	var lift := CargoLift.new()
	lift.size = Vector2(2.6, 2.6)
	lift.top = 7.0
	add_child(lift)
	lift.global_position = Vector3(0, 0.0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("car is ground at the bottom", absf(_ray_y(Vector3(0, 0, 0)) - 0.0) < 0.05, "(%.2f)" % _ray_y(Vector3.ZERO))

	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.6, 0)
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 100000.0
	php.current_health = 100000.0
	var travel := 7.0 / lift.speed
	var low := INF
	var t := 0.0
	while t < travel + 2.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		low = minf(low, player.global_position.y)
		if t > 0.8 and absf(player.global_position.y - 7.0) < 0.3 and lift.at_top():
			break
	print("  ride: player y %.2f after %.1f s (travel %.1f s), lowest %.2f" % [player.global_position.y, t, travel, low])
	_check("player carried to the top landing", absf(player.global_position.y - 7.0) < 0.3, "(y %.2f)" % player.global_position.y)
	_check("never dropped through the car", low > -0.3, "(lowest %.2f)" % low)
	await _wait(0.3)
	_check("car is ground at the top", absf(_ray_y(Vector3(0.5, 0, 0.5)) - 7.0) < 0.05, "(%.2f)" % _ray_y(Vector3(0.5, 0, 0.5)))

	# Step off onto the deck, wait, then stand by the bottom landing: the car
	# (empty at the top) has to come down for you.
	player.global_position = Vector3(-4.0, 7.3, 0)
	await _wait(1.0)
	_check("car waits at the top while you are up there", lift.at_top())
	player.global_position = Vector3(2.8, 0.3, 0) # beside the shaft, on the floor
	var t2 := 0.0
	while t2 < travel + 2.0 and not lift.at_bottom():
		await get_tree().physics_frame
		t2 += get_physics_process_delta_time()
	_check("empty car comes down when called", lift.at_bottom(), "(%.1f s)" % t2)

	# The sea levels' lifts: flush at both ends, the top deck reached by
	# nothing else, and above the flood.
	for id in ["lava_world", "water_world"]:
		await _check_level(id)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()

func _check_level(id: String) -> void:
	var def := LevelDefs.get_def(id)
	var lifts: Array = def.get("lifts", [])
	_check("%s has a lift" % id, lifts.size() >= 1, "(%d)" % lifts.size())
	var flood := -INF
	for t in def.get("tasks", []):
		for w in t.get("waves", []):
			for b in (w.get("flood", {}) as Dictionary).get("beds", []):
				flood = maxf(flood, (b["pos"] as Vector3).y)
	for l in lifts:
		var lp: Vector3 = l["pos"]
		var ls: Vector2 = l.get("size", Vector2(2.6, 2.6))
		var ltop: float = float(l["top"])
		var deck_ok := false
		var base_ok := false
		for p in def.get("platforms", []):
			var pp: Vector3 = p["pos"]
			var ps: Vector3 = p["size"]
			var surf := pp.y + ps.y * 0.5
			# Footprints touch or overlap on the ground plane (0.5 m tolerance).
			var gap_x := absf(pp.x - lp.x) - (ps.x + ls.x) * 0.5
			var gap_z := absf(pp.z - lp.z) - (ps.z + ls.y) * 0.5
			var touching := gap_x <= 0.5 and gap_z <= 0.5
			if touching and absf(surf - ltop) < 0.15:
				deck_ok = true
			if touching and absf(surf - lp.y) < 0.15:
				base_ok = true
		_check("lift top flush beside a deck", deck_ok, "(top %.2f at %s)" % [ltop, lp])
		_check("lift bottom flush with its island", base_ok, "(base %.2f)" % lp.y)
		var reached := false
		for r in def.get("ramps", []) + def.get("stairs", []):
			var to: Vector3 = r.get("to", r.get("pos", Vector3.ZERO))
			if absf(to.y - ltop) < 1.0 and Vector2(to.x - lp.x, to.z - lp.z).length() < 12.0:
				reached = true
		_check("only the lift reaches that deck", not reached)
		if flood > -INF:
			_check("%s lift top stays above the flood" % id, ltop >= flood + 1.0, "(top %.2f, flood %.2f)" % [ltop, flood])
