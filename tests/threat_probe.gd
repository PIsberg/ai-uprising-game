extends Node3D
## Ground-truth ENEMY threat: how fast each robot actually hurts the player.
##
## Enemy damage cannot be read off the scripts — attack_damage stays at the base
## default for most chassis, and the real numbers live in per-enemy vars
## (rocket_damage, projectile_damage, bite damage, beam ticks). So spawn the real
## player, spawn one real robot at its own preferred range, let it fight, and
## measure the damage that actually lands.
##
## Reported as DPS and as "seconds to kill a 100 HP player". Bosses are expected
## to be brutal; a common chassis that out-threatens a boss is a balance bug.
##   godot --headless --path . res://tests/threat_probe.tscn

const WINDOW := 12.0 ## 6 s was not enough for ranged chassis to close and aim
const SKIP := ["archon", "colossus", "manus", "overseer", "smasher", "titan"] # need arenas/phases
const ONLY: Array[String] = [] # debug: restrict to these chassis: restrict to these chassis

var _taken: float = 0.0
var _player: Node3D

func _ready() -> void:
	_run.call_deferred()

func _measure(ename: String) -> float:
	# Re-centre the player every sample. Melee chassis SHOVE it, and a probe that
	# never resets leaves every later robot spawning out of its own reach — the
	# first version of this rig reported 31 of 37 robots as harmless.
	_player.global_position = Vector3.ZERO
	var e: Node3D = (load("res://scenes/enemies/%s.tscn" % ename) as PackedScene).instantiate()
	add_child(e)
	# Sit at the chassis's own preferred engagement distance, facing the player.
	# Spawn at the chassis's OWN preferred range. Clamping this to 22 m put the
	# enemy SNIPER (prefers 34 m) and HOWITZER (32 m) far inside their comfort
	# zone, so they spent the whole sample backing off instead of shooting and
	# read as harmless. Melee and kamikaze chassis (preferred_range ~0) instead
	# get room to close — a SEEKER at 2 m detonates on the spawn frame.
	var pref: float = float(e.get("preferred_range"))
	pref = 8.0 if pref < 4.0 else minf(pref, 40.0)
	e.global_position = Vector3(0, 0, -pref)
	# Face the player by construction. The sight cone's forward is -basis.z of
	# the eye (Godot's -Z convention; the +Z-facing models are flipped inside
	# their scenes), so an identity rotation looks AWAY from a player at +Z:
	# six robots read as harmless in the 2026-09-11 sweep purely because they
	# spawned backwards and fell ATTACK->CHASE->IDLE. look_at() errors on
	# flyers whose basis is still identity, so set the yaw directly.
	e.rotation = Vector3(0, PI, 0)
	_taken = 0.0 # count from the instant it exists — a seeker may pop immediately
	for i in 3:
		await get_tree().physics_frame
	# Hand it the player and drop it straight into its attack state; without a
	# navmesh a robot cannot path, but it can still shoot what it already sees.
	# A kamikaze can already be gone by now.
	if not is_instance_valid(e):
		return _taken / WINDOW
	e.set("target", _player)
	if e.has_method("set_state"):
		e.call("set_state", 4) # State.ATTACK
	var t := 0.0
	while t < WINDOW:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var hp: Node = _player.get_node_or_null("Damageable")
		if hp:
			hp.current_health = 1000000.0 # never die, never respawn
	for i in 40: # rounds in flight land
		await get_tree().physics_frame
	# A SEEKER detonates and frees ITSELF; queue_free on a freed instance is a
	# runtime error that aborts _measure and silently zeroes every chassis
	# measured after it.
	if is_instance_valid(e):
		e.queue_free()
	# Purge everything the sample left behind. The sweep runs alphabetically, and
	# two kinds of bleed corrupted it:
	#   - WARMECH's rockets were still in the air during WHIRLWIND's window.
	#   - A HIVE spawns skitters that outlive it and keep attacking through every
	#     later sample. WHIRLWIND sorts LAST, so it inherited the whole zoo and
	#     read 53 DPS against 27.5 measured in isolation.
	# Free every robot and every round before the next chassis is timed.
	for n in _all_projectiles():
		n.queue_free()
	for n in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(n):
			(n as Node).queue_free()
	for i in 10:
		await get_tree().physics_frame
	return _taken / WINDOW

## Projectiles are plain Area3D nodes parented to the scene root, not grouped.
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

## Without a floor every robot (and the player) free-falls out of engagement
## range inside the sample window and nothing ever lands a shot.
##
## And without a NAVMESH the chassis that have to manoeuvre to attack — the MECH
## charges before it stomps, the ANDROID breaks for cover, the SEEKER has to
## reach you — simply stand still and read as harmless. A bare floor rig said 14
## of 37 robots never landed a hit; most of them were just stuck.
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

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3.ZERO
	# Frozen: it must not run, fall or get knocked around between samples. Its
	# collider still stops rounds and its Damageable still tallies hits.
	_player.set_physics_process(false)
	await get_tree().physics_frame
	var hp: Node = _player.get_node_or_null("Damageable")
	hp.max_health = 1000000.0
	hp.current_health = 1000000.0
	hp.damaged.connect(func(amount: float, _src): _taken += amount)
	# The opening-seconds grace holds every robot's fire; wait it out.
	while GameState.attack_grace_active():
		await get_tree().physics_frame

	var names: Array[String] = []
	for f in DirAccess.get_files_at("res://scenes/enemies/"):
		if f.ends_with(".tscn") and not SKIP.has(f.get_basename()):
			names.append(f.get_basename())
	names.sort()
	if not ONLY.is_empty():
		names = ONLY

	var out: Array = []
	for n in names:
		var dps: float = await _measure(n)
		out.append([dps, n])
	out.sort_custom(func(a, b): return a[0] > b[0])
	print("%-12s %9s %14s" % ["ENEMY", "dmgDPS", "kills 100HP in"])
	var silent: Array[String] = []
	for r in out:
		var dps: float = r[0]
		var n: String = r[1]
		if dps <= 0.0:
			silent.append(n)
			continue
		print("%-12s %9.1f %13.1fs" % [n, dps, 100.0 / dps])
	print("\nnever landed a hit (%d): %s" % [silent.size(), ", ".join(silent)])

	# NOTE: the player is frozen, so these are "if you stand still" numbers — an
	# upper bound. Every chassis is measured identically, so the COMPARISON is
	# what the assertions rest on, not the absolute value.
	var vals: Array[float] = []
	for r in out:
		vals.append(r[0])
	vals.sort()
	var median: float = vals[vals.size() / 2]
	print("median threat = %.1f DPS" % median)

	# REPORT ONLY — deliberately no pass/fail. Two reasons, both learned the hard way:
	#
	# 1. Run-to-run spread on chassis that must manoeuvre is large (a TERMINATOR
	#    read 30.8 and 9.7 across identical runs). Any ratio threshold either flaps
	#    or is so loose it catches nothing.
	# 2. Seven chassis (sniper, sentinel, ripper, mender, howitzer, gunslinger,
	#    enforcer) never land a hit on the FROZEN player here even at their own
	#    preferred range and a 12 s window. They shoot fine in real levels
	#    (campaign_smoke records their hits), so this is a rig limitation, not a
	#    roster of harmless robots. Worth a look on its own some day: do they
	#    refuse to engage a target that never moves?
	#
	# So: read the table, compare rows WITHIN one run, and A/B any change with
	# ONLY set to a single chassis over several runs before believing it. That is
	# how the ALIEN's volley fix was confirmed (4.6/5.5/7.3 -> 14.1/16.3/13.0) and
	# how a WHIRLWIND "nerf" was caught as measurement bleed and reverted.
	get_tree().quit()
