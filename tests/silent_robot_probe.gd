extends Node3D
## Diagnostic-only companion to threat_probe.gd: WHY do sniper, sentinel, ripper,
## mender, howitzer, gunslinger and enforcer never land a hit on the frozen
## player in that rig? Reuses threat_probe's floor/player/frozen-target setup
## (copied here, not shared, so threat_probe stays untouched) and instruments
## each of the seven with per-second telemetry: state, distance, LOS, shots
## fired, and where its rounds ended up. Not a gate -- prints RESULT PASS always.
##   godot --headless --path . res://tests/silent_robot_probe.tscn

const WINDOW := 12.0
const NAMES: Array[String] = ["sniper", "sentinel", "ripper", "mender", "howitzer", "gunslinger", "enforcer"]

## Override the list from the command line to trace any chassis:
##   godot --headless --path . res://tests/silent_robot_probe.tscn -- robots=warbot,alien
func _names() -> Array[String]:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("robots="):
			var out: Array[String] = []
			for n in String(a).trim_prefix("robots=").split(",", false):
				out.append(String(n).strip_edges())
			return out
	return NAMES

var _player: Node3D
var _taken: float = 0.0
var _hit_events: Array = []

func _ready() -> void:
	_run.call_deferred()

func _build_floor() -> void:
	var region := NavigationRegion3D.new()
	add_child(region)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	mi.mesh = pm
	region.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	region.add_child(body)
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	region.navigation_mesh = nm
	region.bake_navigation_mesh()

func _all_projectiles() -> Array[Node]:
	var out: Array[Node] = []
	for c in get_children():
		if c is Projectile:
			out.append(c)
	var scene := get_tree().current_scene
	if scene and scene != self:
		for c in scene.get_children():
			if c is Projectile:
				out.append(c)
	return out

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3.ZERO
	_player.set_physics_process(false)
	await get_tree().physics_frame
	var hp: Node = _player.get_node_or_null("Damageable")
	hp.max_health = 1000000.0
	hp.current_health = 1000000.0
	hp.damaged.connect(func(amount: float, _src): _taken += amount; _hit_events.append(amount))
	while GameState.attack_grace_active():
		await get_tree().physics_frame

	for n in _names():
		await _diagnose(n)

	print("\nRESULT PASS")
	get_tree().quit()

## Prints whatever internal state exists on this chassis (get() on a private
## var just returns null if absent, so one probe body works for all seven).
func _print_telemetry(e: Object, t: float, dist: float, can_see: bool, shots: int) -> void:
	var state_names := ["IDLE", "PATROL", "ALERT", "CHASE", "ATTACK", "STAGGER", "DEAD"]
	var st: int = e.get("state")
	var extra := ""
	for key in ["_charging", "_charge_t", "_volley_n", "_winding", "_windup_t",
			"_burst_remaining", "_seeking_cover", "_dodge_time", "_telegraphing",
			"_tele_timer", "_attack_timer", "_spinning", "_laser_t", "_laser_cd"]:
		var v = e.get(key)
		if v != null:
			extra += " %s=%s" % [key, v]
	print("  t=%5.1f state=%-8s dist=%5.1f see=%s shots=%d%s" %
		[t, state_names[st] if st >= 0 and st < state_names.size() else str(st),
		dist, can_see, shots, extra])

func _diagnose(ename: String) -> void:
	_player.global_position = Vector3.ZERO
	_taken = 0.0
	_hit_events.clear()
	var e: Node3D = (load("res://scenes/enemies/%s.tscn" % ename) as PackedScene).instantiate()
	add_child(e)
	var pref: float = float(e.get("preferred_range"))
	pref = 8.0 if pref < 4.0 else minf(pref, 40.0)
	e.global_position = Vector3(0, 0, -pref)
	e.rotation = Vector3(0, PI, 0) # face the player: sight forward is -Z (see threat_probe)
	for i in 3:
		await get_tree().physics_frame
	print("\n=== %s (preferred_range=%.1f, spawn dist=%.1f) ===" % [ename, float(e.get("preferred_range")), pref])
	if not is_instance_valid(e):
		print("  freed itself before target assignment")
		return
	e.set("target", _player)
	if e.has_method("set_state"):
		e.call("set_state", 4) # State.ATTACK
	var t := 0.0
	var last_print := -1.0
	var shots := 0
	var prev_burst = e.get("_burst_remaining")
	var prev_volley = e.get("_volley_n")
	var proj_seen: Dictionary = {} # instance_id -> true, so we log each once
	var proj_last_pos: Dictionary = {} # instance_id -> [pos, dist_to_player, t] at last sighting
	while t < WINDOW:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if is_instance_valid(_player):
			var php: Node = _player.get_node_or_null("Damageable")
			if php:
				php.current_health = 1000000.0
		if not is_instance_valid(e):
			print("  [t=%.2f] enemy freed itself (kamikaze/despawn)" % t)
			break
		var burst = e.get("_burst_remaining")
		if burst != null and prev_burst != null and int(burst) < int(prev_burst):
			shots += int(prev_burst) - int(burst)
		if burst != null:
			prev_burst = burst
		var volley = e.get("_volley_n")
		if volley != null and prev_volley != null and int(volley) > int(prev_volley):
			shots += int(volley) - int(prev_volley)
		if volley != null:
			prev_volley = volley
		# Track any Projectile this chassis dropped into the scene, and keep
		# updating its last-known position/distance-to-player until it's gone.
		for p in _all_projectiles():
			var id := p.get_instance_id()
			if not proj_seen.has(id):
				proj_seen[id] = true
				shots += 1
				print("    [t=%.2f] spawned projectile %s at %s" % [t, p.get_class(), (p as Node3D).global_position])
			var ppos: Vector3 = (p as Node3D).global_position
			proj_last_pos[id] = [ppos, ppos.distance_to(_player.global_position), t]
		var dist: float = e.global_position.distance_to(_player.global_position)
		var can_see: bool = e.call("_can_see", _player) if e.has_method("_can_see") else false
		if t - last_print >= 1.0:
			last_print = floor(t)
			_print_telemetry(e, t, dist, can_see, shots)
	print("  hits landed on player: %d, total damage: %.1f (%s)" % [_hit_events.size(), _taken, str(_hit_events)])
	print("  total shots/volleys fired: %d" % shots)
	for id in proj_last_pos.keys():
		var rec: Array = proj_last_pos[id]
		print("    projectile %s last seen t=%.2f at %s, %.2fm from player" % [id, rec[2], rec[0], rec[1]])

	if is_instance_valid(e):
		e.queue_free()
	for n in _all_projectiles():
		n.queue_free()
	for n in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(n):
			(n as Node).queue_free()
	for i in 10:
		await get_tree().physics_frame
