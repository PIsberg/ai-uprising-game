extends Node
## CONTINUE works from every campaign level. For each level: build the run
## state a returning player would have (two unlocked bonus weapons, one of them
## equipped, Armory supplies, an upgrade), save it, wipe the singleton, load it
## back as continue_campaign() does, then deploy the real level scene and assert
## the player that spawns actually carries that state: the rack holds both
## bonus weapons, the equipped one is in hand, the supply health is applied,
## the bonus grenades are carried. Backs up and restores the real
## user://savegame.cfg around the whole run.
##   godot --headless --path . --audio-driver Dummy res://tests/continue_sweep_probe.tscn

const BUILD_WAIT := 2.4
const BONUS_A := "res://scenes/weapons/tesla.tscn"
const BONUS_B := "res://scenes/weapons/gauss.tscn"
const SUPPLY_HP := 30.0
const SUPPLY_AMMO := 40
const SUPPLY_GRENADES := 2

var _fail: Array[String] = []
var _save_backup: PackedByteArray = PackedByteArray()
var _had_save := false

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

func _backup_save() -> void:
	_had_save = FileAccess.file_exists(GameState.SAVE_PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_bytes(GameState.SAVE_PATH)

func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(_save_backup)
			f.close()
	else:
		GameState.clear_save()

func _wipe_run() -> void:
	GameState.reset_run()
	GameState.unlocked_weapons.clear()
	GameState.equipped_weapon = ""
	for k in GameState.upgrades:
		GameState.upgrades[k] = 0
	GameState.level_index = 0
	GameState.max_level_reached = 0

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().create_timer(0.25).timeout
		t += 0.25

func _run() -> void:
	_backup_save()
	var campaign: Array = GameState.campaign()
	print("campaign levels: %d" % campaign.size())
	var deployed := 0
	for i in campaign.size():
		var path := String(campaign[i])
		var id := GameState.level_id_from_path(path)
		if not ResourceLoader.exists(path):
			print("  skip %s (no scene)" % id)
			continue
		# --- the run a returning player has ------------------------------
		_wipe_run()
		GameState.unlock_weapon(BONUS_A)
		GameState.unlock_weapon(BONUS_B)
		GameState.equipped_weapon = BONUS_B
		GameState.supply_health = SUPPLY_HP
		GameState.supply_ammo = SUPPLY_AMMO
		GameState.supply_grenades = SUPPLY_GRENADES
		GameState.upgrades["damage"] = 2
		GameState.level_index = i
		GameState.max_level_reached = i
		GameState.save_progress()
		# --- quit, relaunch, Continue -------------------------------------
		_wipe_run()
		var loaded: bool = GameState.load_progress()
		var state_ok: bool = loaded and GameState.level_index == i \
			and GameState.unlocked_weapons.has(BONUS_A) and GameState.unlocked_weapons.has(BONUS_B) \
			and GameState.equipped_weapon == BONUS_B and is_equal_approx(GameState.supply_health, SUPPLY_HP)
		# --- deploy (what load_level does, minus the scene change) --------
		GameState.current_level_path = path
		GameState.reset_level_stats()
		GameState.set_state(GameState.State.PLAYING)
		var lvl: Node = (load(path) as PackedScene).instantiate()
		add_child(lvl)
		await _wait(BUILD_WAIT)
		var player: Node = lvl.find_child("Player", true, false)
		var rack_ok := false
		var equipped_ok := false
		var hp_ok := false
		var nades_ok := false
		var detail := ""
		if player:
			var wm: Node = player.get_node_or_null("Head/Camera3D/WeaponHolder")
			if wm:
				var paths: Array[String] = []
				for w in wm.weapons:
					paths.append(String(w.scene_file_path))
				rack_ok = paths.has(BONUS_A) and paths.has(BONUS_B)
				equipped_ok = wm.current != null and String(wm.current.scene_file_path) == BONUS_B
				detail = "rack=%d" % paths.size()
			var hp: Node = player.get_node_or_null("Damageable")
			if hp:
				hp_ok = hp.max_health >= 100.0 + SUPPLY_HP - 0.01
				detail += " maxhp=%.0f" % hp.max_health
			var g = player.get("grenades")
			var base_g = player.get("max_grenades")
			nades_ok = g != null and base_g != null and int(g) >= int(base_g) + SUPPLY_GRENADES
			detail += " grenades=%s/%s+%d" % [str(g), str(base_g), SUPPLY_GRENADES]
		var ok := state_ok and player != null and rack_ok and equipped_ok and hp_ok and nades_ok
		print("%s %-13s save/load=%s player=%s rack=%s equipped=%s supply_hp=%s grenades=%s  (%s)" % [
			"  ok  " if ok else "  FAIL", id, state_ok, player != null, rack_ok, equipped_ok, hp_ok, nades_ok, detail])
		if not ok:
			_fail.append(id)
		deployed += 1
		# --- teardown (awaited: the next level must not see this one's nodes)
		lvl.queue_free()
		for e in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e):
				e.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	_check(deployed >= 20, "deployed a real campaign (%d levels)" % deployed)
	_wipe_run()
	_restore_save()
	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit()
