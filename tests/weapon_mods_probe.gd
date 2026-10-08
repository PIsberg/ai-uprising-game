extends Node3D
## Weapon mods (GameState.MOD_DEFS, WeaponMods, Armory "WEAPON MODS" row).
## (1) GameState.BASE_LOADOUT matches the rack player.tscn actually builds;
## (2) buy / fit / refit rules, projectile guns refused, save + load round trip;
## (3) each mod's effect, driven through the rifle's real hitscan path:
##     CHAIN ARC hurts a second robot for 35% (not one 20 m away), THERMITE burns
##     30% over 3 s, RICOCHET bounces 60% off a wall into a robot, OVERRIDE turns a
##     robot dropped under 25%; mod damage never counts as a hit for accuracy, and
##     two procs inside PROC_INTERVAL_MS make one.
##   godot --headless --path . --audio-driver Dummy res://tests/weapon_mods_probe.tscn

const RIFLE := "res://scenes/weapons/rifle.tscn"
const SHOTGUN := "res://scenes/weapons/shotgun.tscn"
const PLASMA := "res://scenes/weapons/plasma.tscn"

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# 1. Base loadout twin.
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	var wm = player.find_child("WeaponHolder", true, false)
	var rack: Array[String] = []
	for s in wm.weapon_scenes:
		rack.append((s as PackedScene).resource_path)
	player.free()
	_check("BASE_LOADOUT matches player.tscn's rack", rack == GameState.BASE_LOADOUT, str(rack))

	# 2. Economy and fitting, against a backed-up save file.
	var save_abs := ProjectSettings.globalize_path(GameState.SAVE_PATH)
	var had_save := FileAccess.file_exists(GameState.SAVE_PATH)
	var backup := FileAccess.get_file_as_bytes(GameState.SAVE_PATH) if had_save else PackedByteArray()
	GameState.owned_mods.clear()
	GameState.weapon_mods = {}
	GameState.score = 10000
	_check("projectile launchers take no mod", not GameState.mod_compatible(PLASMA) and GameState.mod_compatible(RIFLE))
	_check("cannot fit an unowned mod", not GameState.fit_mod("arc", RIFLE))
	_check("buy CHAIN ARC", GameState.buy_mod("arc") and GameState.score == 10000 - int(GameState.MOD_DEFS["arc"]["cost"]))
	_check("cannot buy it twice", not GameState.buy_mod("arc"))
	_check("fit ARC to the rifle", GameState.fit_mod("arc", RIFLE) and GameState.mod_for(RIFLE) == "arc")
	_check("refusing a projectile gun", not GameState.fit_mod("arc", PLASMA))
	GameState.buy_mod("thermite")
	GameState.fit_mod("thermite", RIFLE)
	_check("a gun holds one mod: THERMITE replaces ARC", GameState.mod_for(RIFLE) == "thermite" and GameState.mod_fitted_to("arc") == "")
	GameState.fit_mod("arc", SHOTGUN)
	GameState.fit_mod("arc", RIFLE)
	_check("a mod sits on one gun: ARC moved off the shotgun", GameState.mod_for(SHOTGUN) == "" and GameState.mod_for(RIFLE) == "arc")
	GameState.save_progress()
	var want_owned := GameState.owned_mods.duplicate()
	var want_fit := GameState.weapon_mods.duplicate()
	GameState.owned_mods.clear()
	GameState.weapon_mods = {}
	GameState.load_progress()
	_check("mods survive save + load", GameState.owned_mods == want_owned and GameState.weapon_mods == want_fit, "%s %s" % [GameState.owned_mods, GameState.weapon_mods])
	if had_save:
		var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
	else:
		DirAccess.remove_absolute(save_abs)

	# 3. Effects through the real hitscan path.
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(120, 1, 120)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	var shooter := Node3D.new()
	shooter.add_to_group("player")
	add_child(shooter)
	var gun: Weapon = (load(RIFLE) as PackedScene).instantiate()
	add_child(gun)
	gun.global_position = Vector3(0, 1.5, 20)
	gun._active_shooter = shooter
	var a := _robot(Vector3(0, 0, 0))
	var b := _robot(Vector3(4, 0, 0))
	var far := _robot(Vector3(-22, 0, 0))
	await _frames(4)
	var origin := Vector3(0, 1.2, 12)
	var dir := Vector3(0, 0, -1)

	gun.mod_id = "arc"
	var hits0 := GameState.stat_hits
	var b0: float = b.hp.current_health
	var far0: float = far.hp.current_health
	gun._do_hitscan(origin, dir)
	var arc_dmg: float = b0 - b.hp.current_health
	_check("CHAIN ARC hurts the robot 4 m away", arc_dmg > 0.0, "%.1f" % arc_dmg)
	_check("...not the one 22 m away", far.hp.current_health == far0)
	_check("mod damage is not a hit for accuracy", GameState.stat_hits == hits0 + 1, "%d -> %d" % [hits0, GameState.stat_hits])
	b0 = b.hp.current_health
	gun._do_hitscan(origin, dir)
	_check("a second proc inside %d ms does nothing" % WeaponMods.PROC_INTERVAL_MS, b.hp.current_health == b0)

	_heal([a, b, far])
	gun.mod_id = "thermite"
	gun.mod_last_proc_ms = -100000
	var a_before: float = a.hp.current_health
	gun._do_hitscan(origin, dir)
	var hit_dmg: float = a_before - a.hp.current_health
	var after_hit: float = a.hp.current_health
	for i in 18:
		await get_tree().create_timer(0.2).timeout
	var burned: float = after_hit - a.hp.current_health
	# Each tick loses the chassis armour, so allow that much under the nominal total.
	var want := hit_dmg * WeaponMods.BURN_FRACTION
	var ticks := int(WeaponMods.BURN_TIME / WeaponMods.BURN_TICK)
	_check("THERMITE burns %.0f%% of the hit over %.0f s" % [WeaponMods.BURN_FRACTION * 100.0, WeaponMods.BURN_TIME],
		burned <= want + 0.01 and burned >= want - ticks * a.hp.armor - 0.01, "hit %.1f burn %.1f want %.1f" % [hit_dmg, burned, want])

	_heal([a, b, far])
	gun.mod_id = "ricochet"
	gun.mod_last_proc_ms = -100000
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wbs := BoxShape3D.new()
	wbs.size = Vector3(1, 4, 6)
	wcs.shape = wbs
	wall.add_child(wcs)
	add_child(wall)
	wall.global_position = Vector3(-10, 2, 12) # a wall to the left of the gun
	await _frames(3)
	var near_wall := _robot(Vector3(-4, 0, 9)) # off the bounce line from the wall
	await _frames(3)
	var n0: float = near_wall.hp.current_health
	gun._do_hitscan(Vector3(-2, 1.2, 12), Vector3(-1, 0, -0.35).normalized())
	_check("RICOCHET bounces off the wall into a robot", near_wall.hp.current_health < n0, "%.1f" % (n0 - near_wall.hp.current_health))

	_heal([a, b, far])
	gun.mod_id = "override"
	a.hp.current_health = a.hp.max_health * 0.3
	gun._do_hitscan(origin, dir)
	_check("OVERRIDE turns a robot dropped under 25%%", a.get("hijacked") == true, "hp %.0f/%.0f" % [a.hp.current_health, a.hp.max_health])

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _robot(pos: Vector3) -> EnemyBase:
	var e: EnemyBase = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	# AI off, collision on: a disabled body is otherwise REMOVED from physics, and
	# the rifle's ray would pass straight through it.
	e.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	e.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(e)
	e.global_position = pos
	return e

func _heal(es: Array) -> void:
	for e in es:
		(e as EnemyBase).hp.current_health = (e as EnemyBase).hp.max_health
