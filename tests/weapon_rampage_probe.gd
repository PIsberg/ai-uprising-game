extends Node
## Probe: the gun charges up with the RAMPAGE streak (Weapon._on_rampage_changed).
## (1) at tier 0 the gun shoots its own colour and wears no rim;
## (2) at a tier, tracers and the muzzle flash take the tier's colour
##     (GameState.RAMPAGE_COLORS, the HUD banner's), the flash grows by
##     RAMPAGE_FLASH_GROW per tier, and every viewmodel mesh wears the rim;
## (3) when the streak breaks, all of it goes back.
##   godot --headless --path . --audio-driver Dummy res://tests/weapon_rampage_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _meshes(w: Weapon) -> Array:
	return w.rim_meshes()

func _rimmed(w: Weapon) -> int:
	var n := 0
	for mi in _meshes(w):
		if (mi as MeshInstance3D).material_overlay == Weapon.RAMPAGE_RIM:
			n += 1
	return n

## The size and tint of the flash the gun puts out now.
func _flash(w: Weapon) -> Node:
	var before := w.muzzle.get_child_count()
	w._play_muzzle()
	return w.muzzle.get_child(before) if w.muzzle.get_child_count() > before else null

func _run() -> void:
	var w: Weapon = (load("res://scenes/weapons/rifle.tscn") as PackedScene).instantiate()
	add_child(w)
	await get_tree().process_frame
	var own := w.data.tracer_color
	_check("viewmodel has meshes", _meshes(w).size() > 0, str(_meshes(w).size()))

	# 1. No streak.
	GameState.rampage_tier = 0
	GameState.rampage_changed.emit(0, "")
	_check("tier 0: its own colour", w.shot_color() == own)
	_check("tier 0: no rim", _rimmed(w) == 0)

	# 2. Tier 2.
	GameState.rampage_tier = 2
	GameState.rampage_changed.emit(2, "UNSTOPPABLE")
	var tier_col: Color = GameState.RAMPAGE_COLORS[1]
	_check("tier 2: shots in the tier colour", w.shot_color() == tier_col)
	_check("tier 2: every viewmodel mesh wears the rim", _rimmed(w) == _meshes(w).size(),
			"%d of %d" % [_rimmed(w), _meshes(w).size()])
	var f := _flash(w)
	_check("tier 2: the flash takes the colour and grows", f != null and f.tint_color == tier_col
			and is_equal_approx(f.size_mult, w.data.muzzle_scale * (1.0 + 2.0 * Weapon.RAMPAGE_FLASH_GROW)),
			"size %.2f" % (f.size_mult if f else -1.0))

	# 3. The streak breaks.
	GameState.rampage_tier = 0
	GameState.rampage_changed.emit(0, "")
	_check("broken streak: own colour back", w.shot_color() == own)
	_check("broken streak: rim off", _rimmed(w) == 0)
	var f0 := _flash(w)
	_check("broken streak: flash back to size", f0 != null and is_equal_approx(f0.size_mult, w.data.muzzle_scale))

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
