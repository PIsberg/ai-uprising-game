extends Node3D
## Probe: the SW-7 Swarm Launcher's signature (SwarmFx, scripts/weapons/fx/swarm_fx.gd):
##   - a volley's three rockets each carry a corkscrew rig that swings the
##     visible body CORK_RADIUS off the true path (the rocket's origin, where
##     its collision is), round the flight axis, turning as time passes, and
##     trails a smoke thread from the body;
##   - the three of a volley are a third of a turn apart;
##   - a robot ahead in homing range gets one lock diamond while rockets home on
##     it (however many), facing the camera; it goes once no rocket holds it;
##   - each rocket goes off in a starburst of shrapnel;
##   - an unsigned launcher's rockets carry no rig, lock nothing, throw nothing.
##   godot --headless --path . --audio-driver Dummy res://tests/swarm_fx_probe.tscn

const SWARM_FX := "res://scripts/weapons/fx/swarm_fx.gd"

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
	cam.look_at_from_position(Vector3(0, 1.5, 3), Vector3(0, 1.5, -30), Vector3.UP)
	var w: Weapon = (load("res://scenes/weapons/swarm.tscn") as PackedScene).instantiate()
	add_child(w)
	var ctl: Weapon = (load("res://scenes/weapons/swarm.tscn") as PackedScene).instantiate()
	ctl.data = ctl.data.duplicate()
	ctl.data.signature_fx = null
	add_child(ctl)
	await get_tree().process_frame
	await get_tree().physics_frame
	_check("the SW-7 carries the Swarm signature",
			w._sig != null and w._sig.get_script() != null and w._sig.get_script().resource_path == SWARM_FX)
	w._active_shooter = null
	ctl._active_shooter = null

	# A volley into the open (no robots yet): the corkscrew.
	var rockets := _volley(w, Vector3(0, 1.5, 0), Vector3(0, 0, -1))
	_check("a volley launches three rockets", rockets.size() == 3, str(rockets.size()))
	var rigs := rockets.map(func(r: Node3D) -> Node: return r.get_node_or_null("SwarmCork"))
	_check("each carries a corkscrew rig", rigs.all(func(x) -> bool: return x != null))
	if rigs.all(func(x) -> bool: return x != null):
		var swung := true
		for i in rockets.size():
			var r: Node3D = rockets[i]
			var body: Node3D = rigs[i].body
			var rel := body.global_position - r.global_position
			var axis := r.global_basis.z.normalized()
			var off := (rel - axis * rel.dot(axis)).length()
			swung = swung and absf(off - SwarmFx.CORK_RADIUS) < 0.02 and absf(rel.dot(axis)) < 0.02
		_check("each body swings CORK_RADIUS off its true path, round the flight axis", swung)
		_check("each trails a smoke thread from its body", rigs.all(func(x) -> bool:
				return x.smoke != null and x.smoke.get_parent() == x.body and not x.smoke.local_coords))
		var phases: Array = rigs.map(func(x) -> float: return fposmod(x.phase, TAU))
		phases.sort()
		var third := TAU / 3.0
		_check("the three are a third of a turn apart",
				absf(phases[1] - phases[0] - third) < 0.01 and absf(phases[2] - phases[1] - third) < 0.01, str(phases))
		var o0: Vector3 = rigs[0].offset()
		rigs[0]._tick(0.05)
		_check("the body turns as time passes", rigs[0].offset().distance_to(o0) > 0.02)
	for r in rockets:
		if is_instance_valid(r):
			r.queue_free()
	await get_tree().process_frame

	# A robot ahead: one lock while the swarm homes on it, gone after.
	var robot := _robot(Vector3(0, 0, -20))
	await get_tree().physics_frame
	var tags: Array = []
	var watch := func(n: Node) -> void:
		if n.get_meta("sig_fx", "") in ["swarm_lock", "swarm_shrapnel"]:
			tags.append(n)
	get_tree().node_added.connect(watch)
	var homing := _volley(w, Vector3(0, 1.5, 0), Vector3(0, 0, -1))
	var lock_seen := false
	var lock_count := 0
	var lock_faces := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000 and homing.any(func(r) -> bool: return is_instance_valid(r)):
		await get_tree().process_frame
		var locks := robot.get_children().filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "swarm_lock")
		if not locks.is_empty():
			lock_seen = true
			lock_count = maxi(lock_count, locks.size())
			var l: Node3D = locks[0]
			var to_cam := (cam.global_position - l.global_position).normalized()
			lock_faces = lock_faces or absf(l.global_basis.z.normalized().dot(to_cam)) > 0.95
	_check("the robot wears a lock while the swarm homes on it", lock_seen)
	_check("only one lock however many rockets hold it", lock_count == 1, str(lock_count))
	_check("the lock faces the camera", lock_faces)
	await _wait(SwarmFx.LOCK_HOLD + 0.3)
	_check("the lock goes once no rocket holds it", robot.get_node_or_null(SwarmFx.LOCK_NAME) == null)
	var shrapnel := tags.filter(func(n) -> bool: return n.get_meta("sig_fx", "") == "swarm_shrapnel")
	_check("each rocket goes off in a starburst of shrapnel", shrapnel.size() == 3, str(shrapnel.size()))
	get_tree().node_added.disconnect(watch)

	# Unsigned.
	tags.clear()
	get_tree().node_added.connect(watch)
	var crk := _volley(ctl, Vector3(0, 1.5, 0), Vector3(0, 0, -1))
	_check("an unsigned launcher's rockets carry no rig",
			crk.size() == 3 and crk.all(func(r: Node) -> bool: return r.get_node_or_null("SwarmCork") == null))
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000 and crk.any(func(r) -> bool: return is_instance_valid(r)):
		await get_tree().process_frame
	await get_tree().process_frame
	get_tree().node_added.disconnect(watch)
	_check("an unsigned volley locks nothing and throws no shrapnel", tags.is_empty(), str(tags.size()))
	await _wait(0.9)
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

## Fire one shot (three rockets) and return them.
func _volley(w: Weapon, origin: Vector3, dir: Vector3) -> Array:
	var before := get_children()
	for i in w.data.pellets:
		w._spawn_projectile(origin, dir)
	return get_children().filter(func(n: Node) -> bool: return not n in before and n.has_method("launch"))

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()

func _robot(at: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 4
	sb.collision_mask = 0
	sb.add_to_group("enemy")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 2.0, 1.2)
	cs.shape = box
	cs.position.y = 1.0
	sb.add_child(cs)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 1.0e6
	sb.add_child(hp)
	add_child(sb)
	sb.global_position = at
	return sb
