extends Node3D
## Accessibility "Damage Taken" slider (GraphicsSettings.damage_taken, 0.5..1.5):
## scales every hit the player takes. Off-campaign the player's other incoming
## multipliers are 1.0, so a real Damageable hit on the real player must land
## at exactly amount * damage_taken. Also checks the setter clamps and that the
## value persists through the settings file. Restores the user's value.
##   godot --headless --path . --audio-driver Dummy res://tests/damage_taken_probe.tscn

var _fail: Array[String] = []

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)

func _hit(hp: Node, amount: float) -> float:
	hp.current_health = hp.max_health
	var before: float = hp.current_health
	hp.apply_damage(amount, self)
	return before - hp.current_health

func _run() -> void:
	var orig: float = GraphicsSettings.damage_taken
	GameState.current_level_path = "" # off-campaign: warm-up and directive mults are 1.0
	GameState.directive = {}
	GameState.directive_id = ""
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	var player: Node3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3.ZERO
	await get_tree().physics_frame
	var hp: Node = player.get_node("Damageable")
	hp.max_health = 1000.0
	hp.armor = 0.0 if "armor" in hp else 0.0
	while GameState.attack_grace_active():
		await get_tree().physics_frame

	GraphicsSettings.set_damage_taken(1.0)
	var d1 := _hit(hp, 40.0)
	GraphicsSettings.set_damage_taken(0.5)
	var d05 := _hit(hp, 40.0)
	GraphicsSettings.set_damage_taken(1.5)
	var d15 := _hit(hp, 40.0)
	print("40 damage lands as: x1.0=%.1f  x0.5=%.1f  x1.5=%.1f" % [d1, d05, d15])
	_check(is_equal_approx(d1, 40.0), "default 1.0 leaves damage unchanged (%.1f)" % d1)
	_check(is_equal_approx(d05, 20.0), "0.5 halves the hit (%.1f)" % d05)
	_check(is_equal_approx(d15, 60.0), "1.5 adds half again (%.1f)" % d15)

	GraphicsSettings.set_damage_taken(0.1)
	_check(is_equal_approx(GraphicsSettings.damage_taken, 0.5), "setter clamps the floor to 0.5")
	GraphicsSettings.set_damage_taken(9.0)
	_check(is_equal_approx(GraphicsSettings.damage_taken, 1.5), "setter clamps the ceiling to 1.5")

	# Persistence: the setter writes settings.cfg; a fresh read must see it.
	GraphicsSettings.set_damage_taken(0.75)
	var cf := ConfigFile.new()
	var persisted := -1.0
	if cf.load(GraphicsSettings.SETTINGS_PATH) == OK:
		persisted = float(cf.get_value("accessibility", "damage_taken", -1.0))
	_check(is_equal_approx(persisted, 0.75), "value persists to the settings file (%.2f)" % persisted)

	GraphicsSettings.set_damage_taken(orig)
	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit()
