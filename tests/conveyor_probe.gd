extends Node3D
## Probe: ConveyorBelt, the moving belt ("conveyors" def key).
## (1) a player standing still on a belt is carried along it at the belt's
##     speed (within 25%) and not sideways;
## (2) an idle robot on the belt is carried too;
## (3) a robot standing beside the belt stays put;
## (4) The Assembly's belt runs through the east bulkhead gap, under its press,
##     toward the dock (+x).
##   godot --headless --path . --audio-driver Dummy res://tests/conveyor_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _wait(t: float) -> void:
	var tt := 0.0
	while tt < t:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	var belt := ConveyorBelt.new()
	belt.size = Vector2(30.0, 4.0) # long along x
	belt.speed = 3.0
	add_child(belt)
	belt.global_position = Vector3(0, 0, 0)

	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(-10, 0.3, 0)
	await _wait(0.5)
	var p0 := player.global_position
	await _wait(2.0)
	var d := player.global_position - p0
	print("  player moved %s in 2 s" % d)
	_check("player carried along the belt", absf(d.x / 2.0 - 3.0) < 0.75, "(%.2f m/s)" % (d.x / 2.0))
	_check("player not carried sideways", absf(d.z) < 0.3, "(%.2f m)" % d.z)
	player.queue_free()

	var on: CharacterBody3D = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	var off: CharacterBody3D = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	add_child(on)
	add_child(off)
	on.global_position = Vector3(-10, 0.3, 0)
	off.global_position = Vector3(-10, 0.3, 6)
	await _wait(0.5)
	var o0 := on.global_position
	var f0 := off.global_position
	await _wait(2.0)
	var od := on.global_position - o0
	var fd := off.global_position - f0
	print("  robot on the belt moved %s, beside it %s" % [od, fd])
	_check("idle robot carried along the belt", od.x > 3.0, "(%.2f m)" % od.x)
	_check("robot beside the belt stays put", Vector2(fd.x, fd.z).length() < 0.3, "(%.2f m)" % Vector2(fd.x, fd.z).length())

	var def := LevelDefs.get_def("assembly")
	var belts: Array = def.get("conveyors", [])
	_check("assembly has a conveyor", belts.size() >= 1, "(%d)" % belts.size())
	var through := false
	for b in belts:
		var bp: Vector3 = b["pos"]
		var bs: Vector2 = b["size"]
		var dir: Vector2 = b.get("dir", Vector2(1, 0))
		for p in def.get("presses", []):
			var pp: Vector3 = p["pos"]
			if absf(pp.x - bp.x) < bs.x * 0.5 and absf(pp.z - bp.z) < bs.y * 0.5 and dir.x > 0.9:
				for g in def.get("gates", []):
					if String(g["axis"]) == "x" and absf(float(g["at"]) - pp.x) < 1.0 \
							and bp.x - bs.x * 0.5 < float(g["at"]) and bp.x + bs.x * 0.5 > float(g["at"]):
						through = true
	_check("belt runs east through the bulkhead gap under its press", through)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
