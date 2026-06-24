extends Node
## Headless smoke test for the weapon-rack power sort + the HUD weapon carousel.
## Run: godot --headless --path . res://tests/weapon_order_probe.gd
## Grants the full arsenal, spawns the real player + HUD, then asserts the rack is
## ordered weakest→strongest (number keys 1-9) and that the carousel built a cell
## per weapon. Prints PASS/FAIL lines and quits with code 0 on success.

func _ready() -> void:
	# Warp-style full arsenal so the rack holds every weapon.
	GameState.unlock_all_weapons()
	var player_ps: PackedScene = load("res://scenes/player/player.tscn")
	var player := player_ps.instantiate()
	player.add_to_group("player")
	add_child(player)
	var hud_ps: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud := hud_ps.instantiate()
	add_child(hud)
	# Let _ready chains, the rack sort, and the carousel build run.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var failures := 0

	var wm := player.get_node_or_null("Head/Camera3D/WeaponHolder")
	if wm == null:
		print("FAIL: no WeaponManager")
		_finish(1)
		return
	var names: Array = []
	var ranks: Array = []
	for w in wm.weapons:
		names.append(w.scene_file_path.get_file().get_basename())
		ranks.append(GameState.weapon_power_rank(w.scene_file_path))
	print("RACK ORDER (key 1..N): ", names)
	print("RANKS:                 ", ranks)
	# Assert monotonic non-decreasing rank → weak→strong.
	for i in range(1, ranks.size()):
		if ranks[i] < ranks[i - 1]:
			print("FAIL: rack not weak→strong at slot %d (%s)" % [i + 1, names[i]])
			failures += 1
	if failures == 0:
		print("PASS: rack is ordered weakest→strongest")

	# Carousel: one cell per weapon, highlight on the armed slot.
	if "_carousel_cells" in hud:
		var cells: int = hud._carousel_cells.size()
		if cells == wm.weapons.size():
			print("PASS: carousel built %d cells (one per weapon)" % cells)
		else:
			print("FAIL: carousel has %d cells, expected %d" % [cells, wm.weapons.size()])
			failures += 1
	else:
		print("FAIL: HUD has no _carousel_cells")
		failures += 1

	# Energy/laser/arc beam FX must run without error on a hitscan energy weapon.
	var gauss := _find_weapon(wm, "gauss")
	if gauss:
		gauss._energy_beam_flash(Vector3.ZERO, Vector3(0, 0, -8))
		print("PASS: energy_beam_flash ran (gauss)")
	var arc := _find_weapon(wm, "arccoil")
	if arc:
		arc._energy_beam_flash(Vector3.ZERO, Vector3(0, 0, -8))
		print("PASS: arc beam flash ran (arccoil)")
	await get_tree().process_frame

	# Range identity: close shredder strong near / weak far; long gun weak near / full far.
	var sg := _find_weapon(wm, "shotgun")
	if sg:
		var near: float = sg._range_mult(4.0)
		var far: float = sg._range_mult(34.0)
		if near > 0.95 and far < 0.7:
			print("PASS: shotgun falloff near=%.2f far=%.2f" % [near, far])
		else:
			print("FAIL: shotgun falloff near=%.2f far=%.2f" % [near, far]); failures += 1
	var sn := _find_weapon(wm, "sniper")
	if sn:
		var close: float = sn._range_mult(4.0)
		var long: float = sn._range_mult(120.0)
		if close < 0.7 and long > 0.95:
			print("PASS: sniper falloff close=%.2f long=%.2f" % [close, long])
		else:
			print("FAIL: sniper falloff close=%.2f long=%.2f" % [close, long]); failures += 1

	# Run-dry → quick-draw a loaded backup, and the equip lock engages.
	var before = wm.current
	before.mag = 0
	before.reserve = 0
	wm._equip_timer = 0.0
	wm._auto_switch_dry()
	# A good panic pick performs well at close range (full-ish damage at ~6 m) — this
	# rules out the down-ranked long guns (sniper/gauss ≈ 0.6) without over-constraining
	# the archetype (a fast mid-range gun that's lethal up close is a fine pick).
	var picked_close: bool = wm.current and wm.current.data and wm.current._range_mult(6.0) >= 0.85
	if wm.current != before and (wm.current.mag > 0 or wm.current.reserve > 0) and picked_close:
		print("PASS: run-dry auto-switched %s -> %s (close-range pick)" % [
			before.scene_file_path.get_file().get_basename(),
			wm.current.scene_file_path.get_file().get_basename()])
	else:
		print("FAIL: run-dry picked %s (wanted a loaded close-range weapon)" % [
			wm.current.scene_file_path.get_file().get_basename() if wm.current else "<null>"]); failures += 1
	if wm._equip_timer > 0.0:
		print("PASS: equip lock active after switch (%.2fs)" % wm._equip_timer)
	else:
		print("FAIL: equip lock not set after switch"); failures += 1

	print("=== %s ===" % ("ALL PASS" if failures == 0 else "%d FAILURE(S)" % failures))
	_finish(0 if failures == 0 else 1)

func _find_weapon(wm: Node, key: String) -> Node:
	for w in wm.weapons:
		if w.scene_file_path.get_file().get_basename() == key:
			return w
	return null

func _finish(code: int) -> void:
	get_tree().quit(code)
