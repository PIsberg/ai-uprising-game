extends Node3D
## Accessibility "Damage Number Size" (GraphicsSettings.damage_number_scale,
## 0.6..2.0): scales the floating damage numbers Damageable spawns on a hit.
## They render with fixed_size, so pixel_size is the on-screen size; the probe
## deals a real hit to a real Damageable and reads the Label3D it spawned.
## Also checks the setter clamps and the value persists. Restores the value.
##   godot --headless --path . --audio-driver Dummy res://tests/damage_number_size_probe.tscn

const BASE_PIXEL := 0.0028

var _fail: Array[String] = []

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

func _spawn_number(scale_setting: float) -> Label3D:
	GraphicsSettings.set_damage_number_scale(scale_setting)
	var body := Node3D.new()
	add_child(body)
	var d := Damageable.new()
	d.name = "Damageable"
	d.max_health = 1000.0
	body.add_child(d)
	d.current_health = d.max_health
	d.apply_damage(25.0, self)
	var found: Label3D = null
	for c in get_tree().current_scene.get_children():
		if c is Label3D:
			found = c
	return found

func _run() -> void:
	add_to_group("player") # damage numbers only appear for hits the PLAYER deals
	var orig: float = GraphicsSettings.damage_number_scale
	var orig_on: bool = GraphicsSettings.damage_numbers_enabled
	GraphicsSettings.set_damage_numbers_enabled(true)
	GameState.set_state(GameState.State.PLAYING)

	var l1 := _spawn_number(1.0)
	_check(l1 != null, "a hit spawns a floating damage number")
	if l1:
		_check(is_equal_approx(l1.pixel_size, BASE_PIXEL), "default 1.0 keeps the stock size (%.4f)" % l1.pixel_size)
		l1.queue_free()
	await get_tree().process_frame
	var l2 := _spawn_number(2.0)
	if l2:
		_check(is_equal_approx(l2.pixel_size, BASE_PIXEL * 2.0), "2.0 doubles the on-screen size (%.4f)" % l2.pixel_size)
		l2.queue_free()
	else:
		_check(false, "a hit spawns a number at 2.0")
	await get_tree().process_frame
	var l3 := _spawn_number(0.6)
	if l3:
		_check(is_equal_approx(l3.pixel_size, BASE_PIXEL * 0.6), "0.6 shrinks it (%.4f)" % l3.pixel_size)
		l3.queue_free()
	else:
		_check(false, "a hit spawns a number at 0.6")

	GraphicsSettings.set_damage_number_scale(0.1)
	_check(is_equal_approx(GraphicsSettings.damage_number_scale, 0.6), "setter clamps the floor to 0.6")
	GraphicsSettings.set_damage_number_scale(9.0)
	_check(is_equal_approx(GraphicsSettings.damage_number_scale, 2.0), "setter clamps the ceiling to 2.0")
	GraphicsSettings.set_damage_number_scale(1.4)
	var cf := ConfigFile.new()
	var persisted := -1.0
	if cf.load(GraphicsSettings.SETTINGS_PATH) == OK:
		persisted = float(cf.get_value("accessibility", "damage_number_scale", -1.0))
	_check(is_equal_approx(persisted, 1.4), "value persists to the settings file (%.2f)" % persisted)

	GraphicsSettings.set_damage_number_scale(orig)
	GraphicsSettings.set_damage_numbers_enabled(orig_on)
	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit()
