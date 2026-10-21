extends Node3D
## Report: how long each robot goes without attacking a player standing in the
## open. A robot that holds fire while it repositions can fall silent for many
## seconds (the android's flank ran 11.6 s, #414); DPS sweeps (threat_probe)
## average that away. Per chassis, on a baked navmesh, at its own preferred
## range for WINDOW s against an invulnerable still player:
##   shots  things it put into the scene (tracers, projectiles, beams), so a miss counts
##   gap    the longest stretch with nothing put in the scene, tail included
##   hits   damage events on the player, and the longest stretch between them
## Flags SILENT when gap > FLAG_GAP. Report only (no RESULT line): read the flags.
##   godot --headless --path . --audio-driver Dummy res://tests/enemy_silence_report.tscn [-- only=android,gunner]

const WINDOW := 20.0
const FLAG_GAP := 6.0
const SKIP := ["archon", "colossus", "manus", "overseer", "smasher", "titan", "terminator"]

var _t := 0.0
var _events: Array[float] = []
var _hits: Array[float] = []
var _player: CharacterBody3D
var _robot: Node = null

func _ready() -> void:
	_run.call_deferred()

func _physics_process(delta: float) -> void:
	_t += delta

func _run() -> void:
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5).split(",")
	await _nav_floor(160.0)
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3.ZERO # feet on the floor: physics is off, so y 1.0 would float it
	_player.set_physics_process(false)
	var hp := _player.get_node("Damageable") as Damageable
	hp.invulnerable = false
	hp.damaged.connect(func(_a: float, _s: Node) -> void: _hits.append(_t))
	get_tree().node_added.connect(_on_node_added)
	var names: Array[String] = []
	for f in DirAccess.get_files_at("res://scenes/enemies"):
		if f.ends_with(".tscn"):
			var n := f.get_basename()
			if n in SKIP or (not only.is_empty() and not n in only):
				continue
			names.append(n)
	names.sort()
	for n in names:
		await _measure(n)
	print("done")
	get_tree().quit()

func _measure(ename: String) -> void:
	_player.global_position = Vector3.ZERO # feet on the floor: physics is off, so y 1.0 would float it
	var e: Node3D = (load("res://scenes/enemies/%s.tscn" % ename) as PackedScene).instantiate()
	add_child(e)
	var pref: float = float(e.get("preferred_range")) if e.get("preferred_range") != null else 10.0
	pref = 8.0 if pref < 4.0 else minf(pref, 40.0)
	e.global_position = Vector3(0, 0.1, -pref)
	e.rotation = Vector3(0, PI, 0)
	_robot = e
	for i in 3:
		await get_tree().physics_frame
	_events.clear()
	_hits.clear()
	_t = 0.0
	if is_instance_valid(e):
		e.set("target", _player)
		if e.has_method("set_state"):
			e.call("set_state", 4)
	while _t < WINDOW:
		await get_tree().physics_frame
		(_player.get_node("Damageable") as Damageable).current_health = 1000000.0
	var gap := _longest_gap(_events)
	var hgap := _longest_gap(_hits)
	var flag := "  SILENT" if gap > FLAG_GAP else ""
	print("%-16s shots %3d  gap %5.1f s   hits %3d  hit-gap %5.1f s%s" % [ename, _events.size(), gap, _hits.size(), hgap, flag])
	_robot = null
	for n in get_children():
		if n != _player and not n is NavigationRegion3D:
			n.queue_free()
	for n in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(n):
			(n as Node).queue_free()
	for i in 10:
		await get_tree().physics_frame

func _longest_gap(ts: Array[float]) -> float:
	var g := 0.0
	var last := 0.0
	for x in ts:
		g = maxf(g, x - last)
		last = x
	return maxf(g, WINDOW - last)

## Anything new parented straight to the scene root while a robot fights is
## its attack: tracers, projectiles, beams, mines (the robot's own FX hang
## under the robot). Robots added as minions are skipped.
func _on_node_added(n: Node) -> void:
	if _robot == null or n.get_parent() != self or n == _robot or n.is_in_group("enemy"):
		return
	_events.append(_t)

## A baked navmesh floor, so movers path for real.
func _nav_floor(size: float) -> void:
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	fmi.mesh = pm
	nav.add_child(fmi)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size, 1, size)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	sb.add_child(cs)
	nav.add_child(sb)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nm.agent_radius = 0.5
	nm.cell_size = 0.25
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh(false)
	for i in 3:
		await get_tree().physics_frame
