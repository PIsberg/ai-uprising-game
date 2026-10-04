extends Node3D
## Firewall barriers (firewall_barrier.gd): blocks the player, lets robots
## through, and drops on its relay node or its linked objective. Then, for every
## campaign level that authors "firewalls", proves no firewall can lock the
## player out: each opener (relay node, or the objective it waits on) and each
## objective must be reachable from spawn on the live navmesh while crossing only
## firewalls that can already be opened by then.
##   godot --headless --path . --audio-driver Dummy res://tests/firewall_probe.tscn

var _fails: Array[String] = []

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	await _unit()
	await _campaign()
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _body(mask: int, layer: int, at: Vector3) -> CharacterBody3D:
	var b := CharacterBody3D.new()
	b.collision_layer = layer
	b.collision_mask = mask
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	b.add_child(cs)
	add_child(b)
	b.global_position = at
	return b

## Walk bodies toward +Z for `frames` physics ticks at 4 m/s.
func _walk(bodies: Array, frames: int) -> void:
	for i in frames:
		for b in bodies:
			(b as CharacterBody3D).velocity = Vector3(0, -1.0, 4.0)
			(b as CharacterBody3D).move_and_slide()
		await get_tree().physics_frame

func _unit() -> void:
	print("unit:")
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(200, 1, 200)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)

	var ps := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as CollisionObject3D
	var pmask: int = ps.collision_mask
	ps.free()
	_check(pmask & FirewallBarrier.FIREWALL_LAYER != 0, "player.tscn body masks the firewall layer (mask=%d)" % pmask)
	_check(pmask & 16 == 0, "player body does not mask enemy projectiles (layer 5)")

	GameState.reset_tasks()
	var fw := FirewallBarrier.new()
	fw.length = 6.0
	fw.has_relay = true
	fw.node_pos = Vector3(0, 0, -8)
	add_child(fw)
	await _frames(3)
	_check(is_instance_valid(fw.relay), "relay node spawned")

	var runner := _body(pmask, 2, Vector3(0, 0.05, -3))
	var robot := _body(1, 4, Vector3(1.5, 0.05, -3))
	await _walk([runner, robot], 90) # 1.5 s at 60 Hz: 6 m of travel if unobstructed
	_check(runner.global_position.z < 0.0, "player-masked body stopped at the sheet (z=%.2f)" % runner.global_position.z)
	_check(robot.global_position.z > 1.5, "robot-masked body walked through (z=%.2f)" % robot.global_position.z)

	fw.relay.hp.apply_damage(999.0, null)
	await _frames(3)
	_check(fw.is_open, "shooting the relay opened the firewall")
	await _walk([runner], 90)
	_check(runner.global_position.z > 1.5, "player-masked body passes once open (z=%.2f)" % runner.global_position.z)

	GameState.register_task("fw_hack", "test", 0.0)
	var fw2 := FirewallBarrier.new()
	fw2.opens_on = ["fw_hack"]
	fw2.position = Vector3(20, 0, 0)
	add_child(fw2)
	await _frames(2)
	_check(not fw2.is_open, "objective-linked firewall starts closed")
	GameState.complete_task("fw_hack")
	await _frames(2)
	_check(fw2.is_open, "completing the linked objective opened it")

	# Checkpoint resume: the level rebuilds with the opener already done.
	var fw3 := FirewallBarrier.new()
	fw3.opens_on = ["fw_hack"]
	fw3.position = Vector3(40, 0, 0)
	add_child(fw3)
	await _frames(2)
	_check(fw3.is_open, "firewall built after its objective completed starts open")
	for n in [fw, fw2, fw3, runner, robot, floor_body]:
		n.queue_free()
	GameState.reset_tasks()
	await _frames(2)

func _campaign() -> void:
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		if def.get("firewalls", []).is_empty():
			continue
		await _check_level(id, def)

func _task_id(t: Dictionary) -> String:
	var lb := LevelBuilder.new()
	var r := lb._task_id(t)
	lb.free()
	return r

func _check_level(id: String, def: Dictionary) -> void:
	print("level %s:" % id)
	var path := "res://scenes/levels/level_%s.tscn" % id
	var level := (load(path) as PackedScene).instantiate() as Node3D
	add_child(level)
	# Wait for the deferred bake in short physics-frame slices.
	var map := level.get_world_3d().navigation_map
	var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
	for i in 40:
		await _frames(6)
		if NavigationServer3D.map_get_closest_point(map, spawn) != Vector3.ZERO:
			break
	await _frames(10)

	var fws: Array = def["firewalls"]
	var tasks: Array = def.get("tasks", [])
	var by_id := {}
	for t in tasks:
		by_id[_task_id(t)] = t

	# Every task's prerequisite ancestry (ids that are certainly done before it goes live).
	var ancestors := {}
	for t in tasks:
		var seen := {}
		var stack: Array = []
		var a = t.get("after", [])
		stack.append_array([a] if a is String else a)
		while not stack.is_empty():
			var p: String = stack.pop_back()
			if seen.has(p):
				continue
			seen[p] = true
			if by_id.has(p):
				var aa = by_id[p].get("after", [])
				stack.append_array([aa] if aa is String else aa)
		ancestors[_task_id(t)] = seen

	# A firewall is "openable before X" if it has a relay authored earlier in the
	# list than X's index, or its objectives are all ancestors of task X.
	for i in fws.size():
		var fw: Dictionary = fws[i]
		if fw.has("node"):
			var passable: Array = fws.slice(0, i)
			_reach(level, map, spawn, fw["node"], passable, "%s firewall %d relay" % [id, i])
	for t in tasks:
		var tid := _task_id(t)
		var passable: Array = []
		for fw in fws:
			var o = fw.get("opens_on", [])
			var ids: Array = [o] if o is String else o
			var ok: bool = fw.has("node")
			if not ids.is_empty():
				var all_before := true
				for x in ids:
					if not ancestors[tid].has(x):
						all_before = false
				ok = ok or all_before
			if ok:
				passable.append(fw)
		var pts: Array = []
		if t.has("pos"):
			pts.append(t["pos"])
		for p in t.get("points", []):
			pts.append(p["pos"] if p is Dictionary else p)
		for p in pts:
			# Where the builder actually puts it (it rescues buried objectives).
			_reach(level, map, spawn, level._reachable_task_pos(p), passable, "%s task %s" % [id, tid])
	# The exit: every firewall is openable by then.
	_reach(level, map, spawn, def.get("exit", Vector3.ZERO), fws, "%s exit" % id)
	level.queue_free()
	await _frames(4)

func _reach(level: Node3D, map: RID, from: Vector3, to: Vector3, passable: Array, what: String) -> void:
	var a := NavigationServer3D.map_get_closest_point(map, from)
	var b := NavigationServer3D.map_get_closest_point(map, to)
	var p := NavigationServer3D.map_get_path(map, a, b, true)
	var arrived := p.size() > 1 and Vector2(p[-1].x - to.x, p[-1].z - to.z).length() < 3.0
	if not arrived:
		_check(false, "%s: no navmesh path from spawn (target %s, nearest nav %s, route ends %s)"
			% [what, to, b, p[-1] if p.size() > 0 else Vector3.INF])
		return
	var fws: Array = LevelDefs.get_def(level.level_id)["firewalls"]
	for fw in fws:
		if passable.has(fw):
			continue
		for k in range(1, p.size()):
			if _crosses(fw, p[k - 1], p[k]):
				_check(false, "%s: route crosses a firewall at %s that is still closed" % [what, fw["pos"]])
				return
	_check(true, "%s reachable" % what)

func _crosses(fw: Dictionary, p0: Vector3, p1: Vector3) -> bool:
	var c: Vector3 = fw["pos"]
	var half: float = float(fw.get("length", 8.0)) * 0.5
	var yaw := deg_to_rad(float(fw.get("yaw", 0.0)))
	var d := Vector2(cos(yaw), -sin(yaw)) # local +X after a yaw about +Y
	var q0 := Vector2(c.x, c.z) - d * half
	var q1 := Vector2(c.x, c.z) + d * half
	return Geometry2D.segment_intersects_segment(Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), q0, q1) != null