extends Node3D
## Verifies the new signature attacks fire: K-9 pounce, MAITRE-D' cleaver
## throw, sentinel bomb lob, mauler overload detonation.
##   godot --headless --path . --audio-driver Dummy res://tests/signature_attack_probe.tscn

const CASES := {
	"dog": "res://scenes/enemies/dog.tscn",
	"server": "res://scenes/enemies/server.tscn",
	"sentinel": "res://scenes/enemies/sentinel.tscn",
	"mauler": "res://scenes/enemies/mauler.tscn",
}

func _ready() -> void:
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var floor_body := StaticBody3D.new(); floor_body.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(80, 1, 80)
	cs.shape = bs; cs.position = Vector3(0, -0.5, 0); floor_body.add_child(cs)
	nav.add_child(floor_body)
	_run.call_deferred()

func _run() -> void:
	var ok := true
	for key in CASES:
		# Fresh fake player per case (dummy body on layer 2 with a Damageable).
		var player := CharacterBody3D.new()
		player.collision_layer = 2
		player.add_to_group("player")
		var pcs := CollisionShape3D.new(); var cap := CapsuleShape3D.new()
		pcs.shape = cap; player.add_child(pcs)
		var dmg := preload("res://scripts/systems/damageable.gd").new()
		dmg.name = "Damageable"
		dmg.max_health = 10000.0
		player.add_child(dmg)
		add_child(player)
		player.global_position = Vector3(7, 1.0, 0)
		dmg.current_health = 10000.0

		var e: Node3D = load(CASES[key]).instantiate()
		add_child(e)
		e.global_position = Vector3(0, 0.5, 0)
		if key == "mauler":
			await get_tree().create_timer(0.5).timeout
			e.hp.apply_damage(e.hp.max_health * 0.7, self) # trip the overload
		var waited := 0.0
		var fired := false
		while waited < 9.0 and not fired:
			await get_tree().create_timer(0.5).timeout
			waited += 0.5
			match key:
				"dog":
					fired = e.get("_pouncing") or e.get("_pounce_cd") > 0.0
				"server":
					fired = get_tree().root.find_children("*", "ThrownCleaver", true, false).size() > 0 \
						or dmg.current_health < 10000.0
				"sentinel":
					fired = e.get("_volley_n") >= 3 # a bomb went out on volley 3
				"mauler":
					fired = not is_instance_valid(e) or e.get("state") == 5 or e.hp.current_health <= 0.0
		print("%s signature fired=%s (%.1fs, player_hp=%.0f)" % [key, fired, waited, dmg.current_health])
		if not fired:
			ok = false
		if is_instance_valid(e):
			e.queue_free()
		player.queue_free()
		await get_tree().process_frame
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
