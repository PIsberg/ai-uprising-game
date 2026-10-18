extends Node3D
## Probe: SALVAGE guns. A heavy robot in Salvage.TABLE drops its own arm weapon
## when it dies; walking over it puts that gun in your hands for one magazine
## (no reserve, no reload), and the empty gun is tossed back out of the rack.
## (1) data: every salvage scene exists, is a Weapon with a full magazine and no
##     reserve, and is NOT part of the campaign arsenal (WEAPON_ORDER);
## (2) a killed GUNNER drops a SALVAGE pickup carrying the chaingun; a killed
##     android drops nothing;
## (3) walking over it arms the chaingun at once: the rack grows by one, the
##     magazine is full, the reserve is 0, and the gun you carry into the next
##     level (GameState.equipped_weapon) is still your own;
## (4) ammo pickups never top up a salvage gun;
## (5) firing the magazine dry tosses it: the rack shrinks back, the gun you held
##     before is armed again, weapon_removed fired, and the weapon watchdog did
##     not count it as a lost weapon;
## (6) a second salvage replaces the first instead of stacking;
## (7) a salvage pickup nobody takes despawns after Salvage.LIFETIME.
##   godot --headless --path . --audio-driver Dummy res://tests/salvage_probe.tscn

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	# 1. Data.
	var table: Dictionary = Salvage.TABLE
	_check("gunner and mech carry salvage", table.has("gunner") and table.has("mech"))
	_check("Salvage.SALVAGE_KIND is Pickup.Kind.SALVAGE", Salvage.SALVAGE_KIND == Pickup.Kind.SALVAGE)
	for k in table:
		var path := String(table[k]["scene"])
		var w := (load(path) as PackedScene).instantiate() as Weapon
		_check("%s salvage is a weapon" % k, w != null and w.data != null, path)
		if w:
			_check("%s salvage outside the arsenal" % k, not GameState.WEAPON_ORDER.has(path))
			w.free()

	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(120, 1, 120)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	await _frames(10)
	var php: Node = player.get_node("Damageable")
	php.max_health = 100000.0
	php.current_health = 100000.0
	var wm: WeaponManager = player.get_node("Head/Camera3D/WeaponHolder")
	var removed := []
	wm.weapon_removed.connect(func(w) -> void: removed.append(w))
	var own := wm.current
	var own_path := own.scene_file_path
	var rack0 := wm.weapons.size()

	# 2. Drops.
	var gunner := _robot("res://scenes/enemies/gunner.tscn", Vector3(30, 0, 0))
	var android := _robot("res://scenes/enemies/android.tscn", Vector3(-30, 0, 0))
	await _frames(5)
	gunner.hp.apply_damage(999999.0, player, false, gunner.global_position)
	android.hp.apply_damage(999999.0, player, false, android.global_position)
	await _frames(10)
	var drops := _salvage_pickups()
	_check("one salvage drop", drops.size() == 1, "%d" % drops.size())
	if drops.is_empty():
		_finish()
		return
	var drop: Pickup = drops[0] as Pickup
	_check("dropped by the gunner", drop.global_position.distance_to(Vector3(30, 0, 0)) < 3.0, str(drop.global_position))
	_check("it carries the chaingun", drop.weapon_scene and drop.weapon_scene.resource_path == table["gunner"]["scene"])

	# 3. Take it.
	drop._on_body_entered(player)
	await _frames(2)
	var sw := wm.current
	_check("salvage armed at once", sw != null and sw.salvage, sw.name if sw else "none")
	_check("rack grew by one", wm.weapons.size() == rack0 + 1, "%d -> %d" % [rack0, wm.weapons.size()])
	_check("full magazine", sw.mag == sw.data.mag_size, "%d / %d" % [sw.mag, sw.data.mag_size])
	_check("no reserve", sw.reserve == 0, "%d" % sw.reserve)
	_check("next level still gets your own gun", GameState.equipped_weapon == own_path, GameState.equipped_weapon)

	# 4. Ammo pickups skip it.
	for w in wm.weapons:
		w.add_ammo(500)
	_check("ammo never tops up a salvage gun", sw.reserve == 0, "%d" % sw.reserve)

	# 5. Fire it dry.
	var cam: Camera3D = player.get_node("Head/Camera3D")
	var shots := 0
	for i in 2000:
		if not is_instance_valid(sw) or sw.mag <= 0:
			break
		sw._cooldown = 0.0
		sw.try_fire(true, false, cam, player)
		shots += 1
		await get_tree().physics_frame
	await _frames(10)
	_check("the magazine was fired", shots > 0, "%d pulls" % shots)
	_check("dry salvage tossed from the rack", wm.weapons.size() == rack0, "%d" % wm.weapons.size())
	_check("your own gun is back", wm.current == own, wm.current.name if wm.current else "none")
	_check("weapon_removed fired", removed.size() == 1, "%d" % removed.size())
	_check("watchdog saw no lost weapon", wm._watch_rack == wm.weapons.size())

	# 6. A second salvage replaces the first.
	wm.take_salvage(load(String(table["gunner"]["scene"])))
	wm.take_salvage(load(String(table["mech"]["scene"])))
	await _frames(2)
	var n_salvage := wm.weapons.filter(func(w) -> bool: return w.salvage).size()
	_check("one salvage at a time", n_salvage == 1 and wm.weapons.size() == rack0 + 1, "%d salvage, rack %d" % [n_salvage, wm.weapons.size()])
	_check("the newer one is armed", wm.current.scene_file_path == table["mech"]["scene"], wm.current.scene_file_path)

	# 7. Despawn.
	var lone := Salvage.drop_at(self, Vector3(0, 0, 40), "gunner")
	_check("drop_at spawned a pickup", lone != null)
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(lone) and Time.get_ticks_msec() - t0 < int((Salvage.LIFETIME + 3.0) * 1000.0):
		await get_tree().create_timer(0.25).timeout
	_check("an untaken drop despawns", not is_instance_valid(lone), "%.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	_finish()

func _finish() -> void:
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _salvage_pickups() -> Array:
	return get_tree().get_nodes_in_group("pickup").filter(
			func(p) -> bool: return p is Pickup and p.kind == Pickup.Kind.SALVAGE and not p._taken)

func _robot(scene: String, pos: Vector3) -> EnemyBase:
	var e: EnemyBase = (load(scene) as PackedScene).instantiate()
	e.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	add_child(e)
	e.global_position = pos
	e.set_physics_process(false)
	return e
