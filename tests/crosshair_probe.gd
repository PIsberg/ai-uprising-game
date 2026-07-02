extends Node3D
## Windowed visual check: loads level_01, force-equips a few weapons with very
## different spread identities, and screenshots the crosshair each time to
## confirm it now reads the real per-weapon spread/aim/pellet data instead of
## one generic curve.
## Run: godot --path . --quit-after 900 res://tests/crosshair_probe.tscn

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_01.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(1.5).timeout

	var wm := lvl.find_child("WeaponHolder", true, false) # WeaponManager script lives on this node
	if wm == null:
		print("NO WeaponManager found")
		get_tree().quit()
		return

	var by_name := {}
	for w in wm.weapons:
		by_name[w.scene_file_path.get_file().get_basename()] = w

	var hud := lvl.find_child("HUD", true, false)
	if hud == null:
		print("NO HUD found")
		get_tree().quit()
		return
	GameState.current_state = GameState.State.PLAYING
	for id in ["sniper", "pistol", "magnum"]: # level_01's starting loadout (pistol/sniper/magnum)
		if not by_name.has(id):
			print("missing weapon: ", id)
			continue
		wm._equip(wm.weapons.find(by_name[id]))
		hud._on_weapon_changed(by_name[id]) # HUD normally gets this via a signal from wm
		await get_tree().create_timer(0.7).timeout
		hud._update_crosshair(1.0) # force the spread to fully settle for a clean read
		print("%-8s spread_deg=%.1f aim_mult=%.2f -> tick_offset_px=%.2f" % [
			id, by_name[id].data.spread_deg, by_name[id].data.aim_spread_mult,
			-hud._cross_top.offset_bottom - 5.0])

	print("CROSSHAIR_PROBE_DONE")
	get_tree().quit()
