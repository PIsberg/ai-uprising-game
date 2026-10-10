extends Node
## Probe: the railgun's ionization trail (scripts/fx/rail_trail.gd).
## (1) the gauss and the Longshot carry rail_trail, the rifle does not;
## (2) a gauss shot leaves a RailTrail along the round, muzzle to the wall it
##     hit, one mesh whose length matches the shot;
## (3) a rifle shot leaves none;
## (4) a shot longer than MAX_LEN keeps only the MAX_LEN nearest the muzzle;
## (5) at most MAX_LIVE trails live at once (the oldest goes first), and each
##     frees itself after LIFE.
##   godot --headless --path . --audio-driver Dummy res://tests/rail_trail_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _gun(scene: String) -> Weapon:
	var w: Weapon = (load(scene) as PackedScene).instantiate()
	add_child(w)
	return w

func _trails() -> Array:
	return get_tree().get_nodes_in_group(RailTrail.GROUP).filter(func(n: Node) -> bool:
		return not n.is_queued_for_deletion())

func _run() -> void:
	# 1. Which guns.
	var gauss := _gun("res://scenes/weapons/gauss.tscn")
	var sniper := _gun("res://scenes/weapons/sniper.tscn")
	var rifle := _gun("res://scenes/weapons/rifle.tscn")
	await get_tree().process_frame
	_check("gauss and Longshot carry rail_trail, the rifle does not",
			gauss.data.rail_trail and sniper.data.rail_trail and not rifle.data.rail_trail)

	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(20, 20, 1)
	cs.shape = bs
	wall.add_child(cs)
	add_child(wall)
	wall.global_position = Vector3(0, 0, -30.5)
	await get_tree().physics_frame

	# 2. A gauss shot.
	gauss.global_position = Vector3.ZERO
	gauss._do_hitscan(Vector3.ZERO, Vector3.FORWARD)
	var t: Array = _trails()
	_check("a gauss shot leaves one trail", t.size() == 1, str(t.size()))
	if t.size() == 1:
		var rt: RailTrail = t[0]
		var from := gauss.muzzle.global_position if gauss.muzzle else Vector3.ZERO
		_check("it runs from the muzzle to the wall", rt.from.distance_to(from) < 0.01
				and rt.to.distance_to(Vector3(0, 0, -30.0)) < 0.6, "%s -> %s" % [rt.from, rt.to])
		var len := rt.mesh.get_aabb().get_longest_axis_size()
		_check("its mesh is as long as the shot", absf(len - rt.from.distance_to(rt.to)) < 1.0,
				"%.1f vs %.1f" % [len, rt.from.distance_to(rt.to)])

	# 3. A rifle shot.
	rifle._do_hitscan(Vector3.ZERO, Vector3.FORWARD)
	_check("a rifle shot leaves none", _trails().size() == 1, str(_trails().size()))

	# 4. Long shot.
	var far := RailTrail.spawn(self, Vector3.ZERO, Vector3(0, 0, -400), Color.CYAN)
	_check("a 400 m shot keeps MAX_LEN by the muzzle", absf(far.from.distance_to(far.to) - RailTrail.MAX_LEN) < 0.01
			and far.from == Vector3.ZERO, "%.1f" % far.from.distance_to(far.to))

	# 5. Cap and lifetime.
	for i in RailTrail.MAX_LIVE + 3:
		RailTrail.spawn(self, Vector3(i, 0, 0), Vector3(i, 0, -10), Color.CYAN)
	await get_tree().process_frame
	_check("at most MAX_LIVE at once", _trails().size() <= RailTrail.MAX_LIVE, str(_trails().size()))
	for i in int((RailTrail.LIFE + 0.3) * 60.0):
		await get_tree().physics_frame
	_check("each frees itself after LIFE", _trails().is_empty(), str(_trails().size()))

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
