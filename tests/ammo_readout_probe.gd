extends Node3D
## Probe: every gun carries a holographic round counter (Weapon._build_ammo_readout).
## For each gun in GameState.WEAPON_ORDER, built the way the player holds it:
## (1) the readout exists on the viewmodel, on the gun's left flank (left of
##     the fitted box), above its top, within READOUT_REACH of the stock;
## (2) it shows the mag and counts down as the gun fires (the Tesla's beam tick
##     included), in the gun's colour while the mag is healthy;
## (3) at READOUT_LOW it turns red and pulses (alpha moves between frames);
## (4) reloading shows "--", and the full mag comes back when it finishes.
##   godot --headless --path . --audio-driver Dummy res://tests/ammo_readout_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	var shooter := Node3D.new()
	add_child(shooter)
	for p: String in GameState.WEAPON_ORDER:
		var id := p.get_file().get_basename()
		var w: Weapon = (load(p) as PackedScene).instantiate()
		add_child(w)
		await get_tree().process_frame
		var lbl := w.viewmodel.get_node_or_null("AmmoReadout") as Label3D if w.viewmodel else null
		_check("%s has a readout" % id, lbl != null)
		if lbl == null:
			continue
		var box: AABB = w._fit_box
		_check("%s readout sits on the left flank, above the top, near the stock" % id,
			lbl.position.x < box.position.x and lbl.position.y > box.end.y
			and box.end.z - lbl.position.z <= Weapon.READOUT_REACH + 0.001,
			"%s in %s" % [lbl.position, box])
		var full := w.mag
		_check("%s shows the full mag" % id, lbl.text.to_int() == full, "'%s' vs %d" % [lbl.text, full])
		_check("%s is in its own colour while healthy" % id, not lbl.modulate.is_equal_approx(Weapon.READOUT_LOW_COLOR))
		w._cooldown = 0.0
		if w.data.fire_mode == WeaponData.FireMode.BEAM:
			cam.global_position = Vector3(0, 1, 5)
			w._active_camera = cam
			w._beam_wanted = true
			w._beam_tick = 0.0
			w._update_beam(0.001)
			w._beam_wanted = false
		else:
			w._fire_once(cam, shooter, false)
		_check("%s counts down when it fires" % id, lbl.text.to_int() == w.mag and w.mag < full, "'%s' mag %d" % [lbl.text, w.mag])
		w.mag = ceili(w.eff_mag_size() * Weapon.READOUT_LOW)
		w.ammo_changed.emit(w.mag, w.reserve)
		var red := Color(lbl.modulate.r, lbl.modulate.g, lbl.modulate.b).is_equal_approx(Weapon.READOUT_LOW_COLOR)
		var a0 := lbl.modulate.a
		var moved := false
		# The pulse runs on wall-clock ms: sample across 0.4 s, not N frames
		# (headless frames are a few ms each).
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 400:
			await get_tree().process_frame
			moved = moved or absf(lbl.modulate.a - a0) > 0.05
		_check("%s turns red and pulses when low" % id, red and moved, "mag %d alpha moved %s" % [w.mag, moved])
		w.reserve = maxi(w.reserve, w.eff_mag_size())
		w.start_reload()
		_check("%s shows -- while reloading" % id, lbl.text == "--", lbl.text)
		w._finish_reload()
		_check("%s shows the full mag after the reload" % id, lbl.text.to_int() == w.eff_mag_size(), lbl.text)
		w.queue_free()
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
