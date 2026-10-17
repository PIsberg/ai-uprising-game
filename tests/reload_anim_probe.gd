extends Node3D
## Probe: every gun reloads with its own choreography (Weapon._play_reload_anim,
## WeaponData.reload_style). For each gun in GameState.WEAPON_ORDER:
## (1) its reload plays its style's beats in order (reload_beat): MAG
##     mag_out, mag_in, rack; SHELLS one shell per round loaded then pump;
##     CELL vent, charge; TUBE breech, load; all before the reload finishes;
## (2) the gun visibly leaves its pose (>= 0.2 rad of turn) and is back home
##     (within 1 mm and 0.01 rad) when the reload is done;
## (3) a CELL reload drains the gun's glow strips dark and refills them;
## (4) the four styles move the gun differently (no two share a reload pose).
##   godot --headless --path . --audio-driver Dummy res://tests/reload_anim_probe.tscn

const WANT := {
	WeaponData.ReloadStyle.MAG: ["mag_out", "mag_in", "rack"],
	WeaponData.ReloadStyle.CELL: ["vent", "charge"],
	WeaponData.ReloadStyle.TUBE: ["breech", "load"],
}

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	for i in 5:
		await get_tree().process_frame
	var styles := {}
	for p: String in GameState.WEAPON_ORDER:
		var id := p.get_file().get_basename()
		var w: Weapon = (load(p) as PackedScene).instantiate()
		add_child(w)
		await get_tree().process_frame
		var style: int = w.data.reload_style
		styles[style] = true
		var full := w.eff_mag_size()
		w.mag = maxi(0, full - 4) # four rounds short: a shotgun thumbs in four
		w.reserve = full * 2
		var loaded := mini(full - w.mag, w.reserve)
		var beats: Array = []
		w.reload_beat.connect(func(k: String) -> void: beats.append(k))
		var home_pos := w.viewmodel.position
		var max_turn := 0.0
		var min_glow := INF
		var glow0 := _glow(w)
		w.start_reload()
		var t0 := Time.get_ticks_msec()
		var finished_at := -1
		while Time.get_ticks_msec() - t0 < int(maxf(0.6, w.eff_reload_time()) * 1000.0) + 400:
			await get_tree().process_frame
			max_turn = maxf(max_turn, w.viewmodel.rotation.length())
			if glow0 > 0.0:
				min_glow = minf(min_glow, _glow(w))
			if finished_at < 0 and not w._reloading:
				finished_at = beats.size()
		var want: Array = WANT.get(style, [])
		if style == WeaponData.ReloadStyle.SHELLS:
			want = []
			for i in loaded:
				want.append("shell")
			want.append("pump")
		_check("%s reload beats in order" % id, beats == want, "%s vs %s" % [beats, want])
		_check("%s beats all land before the reload finishes" % id, finished_at == want.size(),
			"%d of %d before the end" % [finished_at, want.size()])
		_check("%s visibly moves (%.2f rad)" % [id, max_turn], max_turn >= 0.2)
		_check("%s is back home after the reload" % id, w.viewmodel.position.distance_to(home_pos) < 0.001
			and w.viewmodel.rotation.length() < 0.01, "%s %s" % [w.viewmodel.position - home_pos, w.viewmodel.rotation])
		if style == WeaponData.ReloadStyle.CELL:
			_check("%s cell reload drains its glow strips" % id, glow0 > 0.0 and min_glow < glow0 * 0.2,
				"%.2f -> %.2f" % [glow0, min_glow])
			_check("%s cell reload refills them" % id, is_equal_approx(_glow(w), glow0), "%.2f" % _glow(w))
		w.queue_free()
	_check("all four reload styles are used", styles.size() == 4, str(styles.keys()))
	var poses := {}
	for p in Weapon.RELOAD_POSES:
		poses[str(p)] = true
	_check("no two styles share a reload pose", poses.size() == Weapon.RELOAD_POSES.size())
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _glow(w: Weapon) -> float:
	if w._accent_mats.is_empty():
		return 0.0
	return (w._accent_mats[0] as StandardMaterial3D).emission_energy_multiplier
