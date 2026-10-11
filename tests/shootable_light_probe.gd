extends Node
## Probe: interior ceiling lamps can be shot out, and robots lose a player who
## stands in the dark.
## (1) under a lit lamp the player is not hidden and a robot 20 m away sees it;
## (2) a robot's rounds do not break the lamp; the player's do: its light goes
##     out (energy 0) and the panel stops glowing;
## (3) in the dark the player is hidden: the robot 20 m away no longer sees it,
##     one 6 m away still does (close range), a boss still does;
## (4) firing gives the player away for a moment (muzzle flash), and so does a
##     lit flashlight;
## (5) a blackout lifting (WeatherShift shows its lights again) does not relight
##     a shot-out lamp;
## (6) a level with no shootable lamps (open sky: the sky lights it) is never dark;
## (7) darkness is light taken away: a dim corner no lamp reaches is not a hiding spot;
## (8) a flickering lamp (LevelBuilder._flicker_light) stays out once shot;
## (9) in a real interior level (SUBLEVEL) the luminaires are shootable and
##     shooting the one over the player hides it.
##   godot --headless --path . --audio-driver Dummy res://tests/shootable_light_probe.tscn

const LL_PATH := "res://scripts/systems/light_level.gd"
const SL_PATH := "res://scripts/systems/shootable_light.gd"
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _wait(sec: float) -> void:
	var n := int(ceil(sec / 0.25))
	for i in n:
		await get_tree().create_timer(0.25).timeout

func _ready() -> void:
	_run.call_deferred()

class FakePlayer extends CharacterBody3D:
	var lamp_on := false
	func flashlight_on() -> bool:
		return lamp_on

func _robot(scene: String, pos: Vector3, face: Vector3) -> EnemyBase:
	var e := (load("res://scenes/enemies/%s.tscn" % scene) as PackedScene).instantiate() as EnemyBase
	add_child(e)
	e.global_position = pos
	await _wait(0.75)
	e.set_physics_process(false)
	e.global_position = pos
	e.look_at(Vector3(face.x, pos.y, face.z), Vector3.UP)
	return e

func _sees(e: EnemyBase, p: Node3D) -> bool:
	return e._compute_can_see(p)

func _run() -> void:
	if not ResourceLoader.exists(LL_PATH) or not ResourceLoader.exists(SL_PATH):
		_check("LightLevel and ShootableLight exist", false)
		print("RESULT FAIL")
		get_tree().quit(1)
		return
	var LL: GDScript = load(LL_PATH)
	var SL: GDScript = load(SL_PATH)

	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(120, 1, 120)
	cs.shape = bs
	cs.position.y = -0.5
	floor_body.add_child(cs)
	add_child(floor_body)

	# One ceiling luminaire over the player.
	var light := OmniLight3D.new()
	light.light_energy = 2.4
	light.omni_range = 16.0
	add_child(light)
	light.global_position = Vector3(0, 5.0, 0)
	light.add_to_group("level_light")
	var lamp: Node3D = SL.call("build", self, light, Color(1, 1, 1))

	var p := FakePlayer.new()
	p.add_to_group("player")
	p.collision_layer = 2
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	pcs.shape = cap
	pcs.position.y = 0.9
	p.add_child(pcs)
	add_child(p)
	p.global_position = Vector3(1.0, 0, 0)

	var far := await _robot("gunner", Vector3(1.0, 0, -20.0), p.global_position)
	var near := await _robot("gunner", Vector3(-5.0, 0, 3.0), p.global_position)

	# 1. Lit.
	_check("lit: the player is not hidden", not LL.call("is_hidden", p), "lux %.2f" % LL.call("lux_at", p.global_position))
	_check("lit: a robot 20 m away sees the player", _sees(far, p))

	# 2. Robot fire does not break it; player fire does.
	var hp: Damageable = lamp.get_node("Damageable")
	hp.apply_damage(500.0, far)
	_check("a robot's rounds leave the lamp on", light.light_energy > 1.0, "energy %.2f" % light.light_energy)
	hp.apply_damage(500.0, p)
	await _wait(0.5)
	_check("the player's rounds put the light out", light.light_energy <= 0.0, "energy %.2f" % light.light_energy)
	var panel := lamp.find_child("Panel", true, false) as MeshInstance3D
	var pm := panel.mesh.surface_get_material(0) as StandardMaterial3D if panel and panel.mesh else null
	_check("the lamp's panel stops glowing", pm != null and (not pm.emission_enabled or pm.emission_energy_multiplier < 0.05))

	# 3. Dark.
	GameState.set("_last_shot_ms", -100000) # no recent shot
	_check("dark: the player is hidden", LL.call("is_hidden", p), "lux %.2f" % LL.call("lux_at", p.global_position))
	_check("dark: the robot 20 m away loses the player", not _sees(far, p))
	_check("dark: a robot 6 m away still sees the player", _sees(near, p))
	far.score_value = 1000 # a boss
	_check("dark: a boss still sees the player", _sees(far, p))
	far.score_value = 200

	# 4. Firing and a flashlight give you away.
	GameState.register_shot()
	_check("firing: the muzzle flash gives the player away", not LL.call("is_hidden", p) and _sees(far, p))
	await _wait(2.5)
	_check("firing: hidden again once the flash is past", LL.call("is_hidden", p))
	p.lamp_on = true
	_check("a lit flashlight gives the player away", not LL.call("is_hidden", p))
	p.lamp_on = false

	# 5. A blackout lifting does not relight it.
	light.visible = false
	light.visible = true
	_check("a blackout lifting leaves a shot-out lamp dark", light.light_energy <= 0.0 and LL.call("is_hidden", p))

	# 6. Open sky: no shootable lamps in the level.
	lamp.remove_from_group("shootable_light")
	await _wait(0.5) # past the per-frame caches
	_check("no shootable lamps (open sky): never hidden", not LL.call("is_hidden", p))
	lamp.add_to_group("shootable_light")

	# 7. Out of every lamp's reach: nothing was taken away, so not hidden.
	p.global_position = Vector3(40.0, 0, 0)
	await _wait(0.5)
	_check("a corner no lamp reaches is not a hiding spot", not LL.call("is_hidden", p),
		"full lux %.2f" % LL.call("full_lux_at", p.global_position))

	# 8. A flickering lamp stays out.
	var fl := OmniLight3D.new()
	fl.light_energy = 2.4
	fl.omni_range = 16.0
	add_child(fl)
	fl.global_position = Vector3(60, 5.0, 0)
	fl.add_to_group("level_light")
	var fl_lamp: Node3D = SL.call("build", self, fl, Color(1, 1, 1))
	var ftw := fl.create_tween().set_loops()
	ftw.tween_property(fl, "light_energy", 1.0, 0.05)
	ftw.tween_property(fl, "light_energy", 2.4, 0.05)
	fl.set_meta("flicker_tween", ftw)
	(fl_lamp.get_node("Damageable") as Damageable).apply_damage(500.0, p)
	await _wait(1.5)
	_check("a flickering lamp stays out once shot", fl.light_energy <= 0.0, "energy %.2f" % fl.light_energy)

	# 9. A real interior level.
	for n in [floor_body, light, lamp, fl, fl_lamp, far, near, p]:
		if is_instance_valid(n):
			n.queue_free()
	await _wait(0.5)
	var lvl := (load("res://scenes/levels/level_sublevel.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await _wait(2.0)
	var lamps := get_tree().get_nodes_in_group("shootable_light")
	var player := get_tree().get_first_node_in_group("player") as Node3D
	_check("SUBLEVEL: every luminaire is shootable", lamps.size() >= 8 and player != null, "%d lamps" % lamps.size())
	if not lamps.is_empty() and player:
		var over: Node3D = lamps[0]
		player.global_position = Vector3(over.global_position.x, 0.2, over.global_position.z)
		await _wait(0.5)
		GameState.set("_last_shot_ms", -100000)
		var before: bool = LL.call("is_hidden", player)
		(over.get_node("Damageable") as Damageable).apply_damage(500.0, player)
		await _wait(0.75)
		GameState.set("_last_shot_ms", -100000)
		_check("SUBLEVEL: shooting the lamp overhead hides the player", not before and LL.call("is_hidden", player),
			"before %s, lux %.2f of %.2f" % [before, LL.call("lux_at", player.global_position), LL.call("full_lux_at", player.global_position)])

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
