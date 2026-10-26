extends Node3D
## Probe: the VK-7 Tesla Projector's signature (TeslaFx,
## scripts/weapons/fx/tesla_fx.gd) through the beam's on_beam_tick hook:
##   - holding the beam on a robot wraps it in one electrocution cage (however
##     many ticks land): CAGE_ARCS ArcBolts whose segment ends all lie on or
##     near the robot's bounds, re-zapped every frame (they crawl);
##   - released, the cage crackles on: still there 0.2 s later at reduced
##     strength with fewer arcs lit, and gone within a second;
##   - a beam on a wall cages nothing; an unsigned Tesla (signature cleared)
##     cages nothing;
##   - ArcBolt (scripts/fx/arc_bolt.gd) lays its chain end to end from a to b.
##   godot --headless --path . --audio-driver Dummy res://tests/tesla_fx_probe.tscn

const TESLA_FX := "res://scripts/weapons/fx/tesla_fx.gd"

var ok := true
var cam: Camera3D

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	cam = Camera3D.new()
	add_child(cam)
	cam.make_current()
	var robot := _robot(Vector3(0, 0, -6))
	var wall := _wall(Vector3(0, 1.5, 6))
	var w: Weapon = (load("res://scenes/weapons/tesla.tscn") as PackedScene).instantiate()
	add_child(w)
	var ctl: Weapon = (load("res://scenes/weapons/tesla.tscn") as PackedScene).instantiate()
	ctl.data = ctl.data.duplicate()
	ctl.data.signature_fx = null
	add_child(ctl)
	await get_tree().process_frame
	await get_tree().physics_frame
	_check("the VK-7 carries the Tesla signature",
			w._sig != null and w._sig.get_script() != null and w._sig.get_script().resource_path == TESLA_FX)

	# ArcBolt: the chain runs end to end from a to b.
	var bolt := ArcBolt.make(5, 0.02, Color.CYAN)
	add_child(bolt)
	var a := Vector3(10, 1, 0)
	var b := Vector3(13, 2, 0)
	bolt.zap(a, b, 0.3)
	var pts := bolt.points()
	var chained := pts[0].distance_to(a) < 0.01 and pts[pts.size() - 1].distance_to(b) < 0.01
	for i in range(1, pts.size() - 1, 2):
		chained = chained and pts[i].distance_to(pts[i + 1]) < 0.01
	_check("an ArcBolt lays its chain end to end from a to b", chained)
	bolt.queue_free()

	# Hold the beam on the robot.
	cam.look_at_from_position(Vector3(0, 1.2, 0), Vector3(0, 1.2, -6), Vector3.UP)
	_hold(w, true)
	var cage: Node3D = null
	for i in 40:
		w._update_beam(1.0 / 60.0)
		await get_tree().process_frame
		cage = robot.get_node_or_null(TeslaFx.CAGE_NAME)
	var cages := robot.get_children().filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "tesla_cage")
	_check("holding the beam on a robot wraps it in one cage", cages.size() == 1, str(cages.size()))
	if cage:
		var arcs: Array = cage.arcs
		_check("the cage has CAGE_ARCS arcs", arcs.size() == TeslaFx.CAGE_ARCS, str(arcs.size()))
		var box: AABB = cage.bounds.grow(0.25)
		var on_body := true
		for arc: ArcBolt in arcs:
			for p in arc.points():
				on_body = on_body and box.has_point(robot.to_local(p))
		_check("every arc lies on the robot's body", on_body, str(cage.bounds))
		_check("the cage is lit at full strength while beamed", is_equal_approx(cage.strength(), 1.0) or cage.strength() > 0.9,
				"%.2f" % cage.strength())
		var before: PackedVector3Array = (arcs[0] as ArcBolt).points()
		await get_tree().process_frame
		await get_tree().process_frame
		var after: PackedVector3Array = (arcs[0] as ArcBolt).points()
		_check("the arcs crawl (re-zapped every frame)", before[2].distance_to(after[2]) > 0.001)
		# Release.
		_hold(w, false)
		w._update_beam(1.0 / 60.0)
		await _wait(0.2)
		if is_instance_valid(cage):
			var lit: int = (cage.arcs as Array).filter(func(x: Node3D) -> bool: return x.visible).size()
			_check("released, it crackles on at reduced strength with fewer arcs",
					cage.strength() < 0.9 and cage.strength() > 0.0 and lit < TeslaFx.CAGE_ARCS,
					"strength %.2f, %d arcs lit" % [cage.strength(), lit])
		else:
			_check("released, it crackles on at reduced strength with fewer arcs", false, "gone before 0.2 s")
		await _wait(0.9)
		_check("the cage is gone within a second of release", not is_instance_valid(cage))

	# A wall: no cage anywhere.
	cam.look_at_from_position(Vector3(0, 1.5, 0), Vector3(0, 1.5, 6), Vector3.UP)
	_hold(w, true)
	for i in 20:
		w._update_beam(1.0 / 60.0)
		await get_tree().process_frame
	_hold(w, false)
	w._update_beam(1.0 / 60.0)
	_check("a beam on a wall cages nothing", _cages() == 0 and wall.get_node_or_null(TeslaFx.CAGE_NAME) == null)

	# Unsigned: no cage.
	cam.look_at_from_position(Vector3(0, 1.2, 0), Vector3(0, 1.2, -6), Vector3.UP)
	_hold(ctl, true)
	for i in 20:
		ctl._update_beam(1.0 / 60.0)
		await get_tree().process_frame
	_hold(ctl, false)
	ctl._update_beam(1.0 / 60.0)
	_check("an unsigned Tesla cages nothing", robot.get_node_or_null(TeslaFx.CAGE_NAME) == null)
	_check("the robot took the beam's damage", robot.get_node("Damageable").current_health < 1.0e6)
	await _wait(0.3)
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _hold(w: Weapon, on: bool) -> void:
	w._active_camera = cam
	w._active_shooter = null
	w._beam_wanted = on
	w.mag = maxi(w.mag, 60)

func _cages() -> int:
	return get_tree().root.find_children(TeslaFx.CAGE_NAME, "", true, false).size()

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()

## A robot stand-in with a visible 0.8 x 1.8 x 0.8 body on the enemy layer.
func _robot(at: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 4
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	cs.shape = box
	cs.position.y = 0.9
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.8, 1.8, 0.8)
	mi.mesh = bm
	mi.position.y = 0.9
	sb.add_child(mi)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 1.0e6
	sb.add_child(hp)
	add_child(sb)
	sb.global_position = at
	return sb

func _wall(at: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 6, 0.5)
	cs.shape = box
	sb.add_child(cs)
	add_child(sb)
	sb.global_position = at
	return sb
