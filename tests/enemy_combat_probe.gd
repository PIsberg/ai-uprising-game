extends Node3D
## Live combat test for the new enemies. Spawns each against a player proxy on a
## floor, runs the real AI for a few seconds, and reports: highest AI state
## reached (did it engage?), whether it damaged the player, and whether it dies
## cleanly. Prints RESULT PASS only if every enemy engaged (>=CHASE) and died OK.
##   godot --headless --path . res://tests/enemy_combat_probe.tscn

# dist = spawn distance; need_dmg = require it to hurt the player in this harness.
# Ground MELEE (roller) is spawned within reach because this harness has no baked
# navmesh to path across (real levels bake one). The shark is a water breacher —
# its damage is covered by shark_breach_probe; here we only check engage + death.
const ENEMIES := [
	{"name": "warbot", "fly": false, "dist": 8.0, "need_dmg": true},
	{"name": "enforcer", "fly": false, "dist": 8.0, "need_dmg": true},
	{"name": "ripper", "fly": false, "dist": 8.0, "need_dmg": true},
	{"name": "optic", "fly": false, "dist": 8.0, "need_dmg": true},
	{"name": "gunslinger", "fly": false, "dist": 8.0, "need_dmg": true},
	{"name": "roller", "fly": false, "dist": 2.6, "need_dmg": true},
	{"name": "shark", "fly": true, "dist": 6.0, "need_dmg": false},
	{"name": "whirlwind", "fly": true, "dist": 6.0, "need_dmg": true},
	{"name": "breaker", "fly": true, "dist": 6.0, "need_dmg": true},
]

var _player: Node3D
var _php  # player Damageable

func _ready() -> void:
	# Floor (world layer 1) so ground enemies stand + path with the straight-line fallback.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fb := BoxShape3D.new(); fb.size = Vector3(60, 1, 60)
	fcs.shape = fb
	floor_body.add_child(fcs)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	# Player proxy: group "player", layer 2, with a Damageable so it can be hurt.
	_player = StaticBody3D.new()
	_player.add_to_group("player")
	_player.collision_layer = 2
	var pcs := CollisionShape3D.new()
	var pc := CapsuleShape3D.new(); pc.radius = 0.4; pc.height = 1.8
	pcs.shape = pc
	_player.add_child(pcs)
	_player.position = Vector3(0, 1, 0)
	_php = Node.new()
	_php.set_script(load("res://scripts/systems/damageable.gd"))
	_php.name = "Damageable"
	_php.set("max_health", 100000.0)
	_player.add_child(_php)
	add_child(_player)
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var rows := []
	var all_ok := true
	for spec in ENEMIES:
		var name: String = spec["name"]
		var bot: Node3D = load("res://scenes/enemies/%s.tscn" % name).instantiate()
		add_child(bot)
		bot.global_position = Vector3(float(spec["dist"]), (2.2 if spec["fly"] else 0.6), 0)
		var hp_before: float = _php.get("current_health")
		var max_state := 0
		# Run the real AI for ~6 s.
		for i in 360:
			await get_tree().physics_frame
			var st: int = bot.get("state")
			if st != null and st < 6:  # ignore DEAD when tracking "engaged"
				max_state = maxi(max_state, st)
			if not is_instance_valid(bot):
				break
		var dmg_done: float = hp_before - float(_php.get("current_health"))
		# Kill it and confirm a clean death.
		var died_ok := true
		if is_instance_valid(bot):
			var d = bot.get("hp")
			if d:
				d.apply_damage(999999.0, _player)
			for i in 120:
				await get_tree().physics_frame
				if not is_instance_valid(bot):
					break
			# Either freed, or in DEAD state — both count as a clean death.
			if is_instance_valid(bot):
				var st2: int = bot.get("state")
				died_ok = (st2 == 6)
				bot.queue_free()
		_php.set("current_health", 100000.0)  # reset for the next enemy
		var engaged := max_state >= 3   # CHASE or beyond
		var dmg_ok := (not bool(spec["need_dmg"])) or dmg_done > 0.0
		var ok := engaged and died_ok and dmg_ok
		all_ok = all_ok and ok
		rows.append("%-11s maxstate=%d engaged=%s dmg_to_player=%.0f dmg_ok=%s died_ok=%s %s"
			% [name, max_state, engaged, dmg_done, dmg_ok, died_ok, "OK" if ok else "<-- FAIL"])
	print("---- enemy combat report ----")
	for r in rows:
		print(r)
	print("RESULT ", "PASS" if all_ok else "FAIL")
	get_tree().quit()
