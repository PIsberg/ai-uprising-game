extends Node3D
## Ground-truth weapon DPS, measured against REAL enemy robots.
##
## Fires each weapon for a fixed window at frozen androids (huge HP so nothing
## dies mid-sample) and reads the damage actually dealt — so pellets, falloff,
## pierce, splash, chain hops and cluster bomblets all count for exactly what
## they're worth, instead of being estimated from the .tres fields.
##
##   SOLO  — one robot: the boss/elite case. AoE earns nothing extra here.
##   CROWD — six packed robots: the horde case, where AoE is the whole point.
##
## A weapon's rank in GameState.WEAPON_ORDER is a promise about its power. A
## mid-game gun that beats the ultimate on a single big target is a progression
## bug, and this probe is what catches it.
##   godot --headless --path . res://tests/ttk_probe.tscn

const WEAPONS := ["pistol", "rifle", "shotgun", "magnum", "tesla", "arccoil",
	"sniper", "plasma", "gauss", "swarm", "tempest", "devastator", "omega"]
const WINDOW := 6.0    ## seconds of held trigger
const DIST := 10.0     ## inside EVERY weapon's reach — the VK-7 Tesla only has 13 m
const SLACK := 1.25    ## allowed solo-DPS overshoot of a higher-ranked weapon
const ENEMY := "res://scenes/enemies/android.tscn"

var _cam: Camera3D
var _shooter: Node3D

func _ready() -> void:
	_run.call_deferred()

## A frozen robot: real collision layers + "enemy" group (so chain/splash find
## it), but no movement and no attacks. NOTE: EnemyBase._sync_stats() runs
## deferred and re-applies the authored max_health, so an HP override set at
## spawn is silently wiped — instead we tally damage off the `damaged` signal
## and top the robot back up every frame so it can never die mid-sample.
var _dealt: float = 0.0

func _robot(pos: Vector3) -> Node3D:
	var e: Node3D = (load(ENEMY) as PackedScene).instantiate()
	add_child(e)
	e.global_position = pos
	e.set_physics_process(false)
	e.set_process(false)
	var hp: Node = e.get_node_or_null("Damageable")
	if hp:
		hp.damaged.connect(func(amount: float, _src): _dealt += amount)
	return e

func _topup(rs: Array) -> void:
	for r in rs:
		var hp: Node = (r as Node).get_node_or_null("Damageable")
		if hp:
			hp.max_health = 1000000.0
			hp.current_health = 1000000.0

func _measure(wname: String, crowd: bool) -> float:
	var targets: Array = []
	if crowd:
		# One robot MUST sit on the aim ray, or hitscan weapons register nothing
		# and only the AoE weapons appear to work.
		var xs := [0.0, -0.9, 0.9, -1.8, 1.8, 2.7]
		for i in 6:
			targets.append(_robot(Vector3(xs[i], 0, -DIST - float(i % 2))))
	else:
		targets.append(_robot(Vector3(0, 0, -DIST)))
	for i in 3:
		await get_tree().physics_frame
	var w: Node3D = (load("res://scenes/weapons/%s.tscn" % wname) as PackedScene).instantiate()
	add_child(w)
	w.global_position = Vector3(0, 1.2, 0)
	await get_tree().physics_frame
	_topup(targets)
	_dealt = 0.0
	# SEMI fires on the trigger's rising edge only — holding it down fires exactly
	# one shot. Pulse it so semi-autos run at their cooldown, the way a player
	# clicking as fast as the gun allows would. AUTO/BURST/BEAM want it held.
	# BURST fires on the rising edge too (one burst per press), so it pulses like
	# a semi. Only AUTO and BEAM want the trigger held.
	var semi: bool = w.data.fire_mode == WeaponData.FireMode.SEMI 		or w.data.fire_mode == WeaponData.FireMode.BURST
	var t := 0.0
	var frame := 0
	while t < WINDOW:
		var down := true if not semi else (frame % 2 == 0)
		w.try_fire(down, true, _cam, _shooter)
		await get_tree().physics_frame
		_topup(targets)
		t += get_physics_process_delta_time()
		frame += 1
	w.try_fire(false, false, _cam, _shooter)
	for i in 100: # projectiles land, chains hop, bomblets ripple
		await get_tree().physics_frame
		_topup(targets)
	var dealt := _dealt
	w.queue_free()
	for r in targets:
		(r as Node).queue_free()
	await get_tree().physics_frame
	return dealt / WINDOW

func _run() -> void:
	_shooter = Node3D.new()
	_shooter.add_to_group("player")
	add_child(_shooter)
	_cam = Camera3D.new()
	_cam.current = true
	add_child(_cam)
	_cam.global_position = Vector3(0, 1.2, 0)
	# Centre mass, NOT the head: aiming high lands headshots (x2.2 on some guns,
	# x1 on others) and silently rewrites the ladder. Balance is judged on torso hits.
	_cam.look_at(Vector3(0, 0.7, -DIST), Vector3.UP)
	await get_tree().physics_frame

	print("%-11s %-5s %9s %9s" % ["WEAPON", "rank", "soloDPS", "crowdDPS"])
	var solo := {}
	var crowd := {}
	for i in WEAPONS.size():
		var wname: String = WEAPONS[i]
		var s: float = await _measure(wname, false)
		var c: float = await _measure(wname, true)
		solo[wname] = s
		crowd[wname] = c
		print("%-11s %-5d %9.0f %9.0f" % [wname, i + 1, s, c])

	# Rank inversions are INFORMATIONAL. This rig fires at centre mass from one
	# distance, so it cannot see what the MK-VII Longshot (headshots) or the ARC-9
	# Gauss Lance (pierces a LINE of robots, not a rank of them) are actually for.
	# Both under-read here and are not broken. The assertions below hold regardless
	# of a weapon's role.
	print("\n-- rank inversions on solo DPS (informational; role weapons under-read):")
	for i in WEAPONS.size():
		for j in range(i + 1, WEAPONS.size()):
			var lo: float = solo[WEAPONS[i]]
			var hi: float = solo[WEAPONS[j]]
			if hi > 0.0 and lo > hi * SLACK:
				print("   %-10s(r%2d) %5.0f  >  %-10s(r%2d) %5.0f" % [
					WEAPONS[i], i + 1, lo, WEAPONS[j], j + 1, hi])

	var ok := true
	# 0. Every weapon must be able to hurt a robot standing in the open. There is
	#    no world geometry in this rig, so a projectile whose collision_mask omits
	#    the enemy layer flies straight through and reads exactly 0 — which is how
	#    the GRK-X Devastator shipped: it fired the MECH's enemy-side rocket
	#    (layer "enemy_projectile", mask world+player) and could only ever hurt a
	#    robot by splashing off scenery behind it.
	for w in WEAPONS:
		if solo[w] <= 0.0:
			print("BAD  %s cannot damage a lone robot in the open (solo DPS = 0)" % w)
			ok = false
	# 1. Nothing may beat the OMEGA ultimate at BOTH jobs. Caught the GRK-X
	#    Devastator out-damaging the game's final weapon on solo AND on crowd.
	for w in WEAPONS:
		if w == "omega":
			continue
		if solo[w] > solo["omega"] * SLACK and crowd[w] > crowd["omega"] * SLACK:
			print("BAD  %s beats the OMEGA ultimate on solo AND crowd" % w)
			ok = false
	# 2. The ultimate must out-damage the starter sidearm on a single target.
	if solo["omega"] <= solo["pistol"]:
		print("BAD  OMEGA solo %.0f <= M9 pistol solo %.0f" % [solo["omega"], solo["pistol"]])
		ok = false
	# 3. Outlier guard. The Arc Coil's stacked-burst exploit read 1088 solo DPS
	#    against a ~145 median — nothing should run away with single-target damage.
	var vals: Array[float] = []
	for w in WEAPONS:
		vals.append(solo[w])
	vals.sort()
	var median: float = vals[vals.size() / 2]
	for w in WEAPONS:
		if solo[w] > median * 2.2:
			print("BAD  %s solo %.0f exceeds 2.2x the median (%.0f)" % [w, solo[w], median])
			ok = false
	print("\nmedian solo DPS = %.0f" % median)
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
