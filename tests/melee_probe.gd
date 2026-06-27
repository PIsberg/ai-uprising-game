extends Node3D
## Verifies the new melee shove: spawns enemies in a cone in front of the player,
## fires _do_melee(), and checks they take damage + get knocked back, while an
## enemy behind / out of range is untouched.
## Headless: godot --headless --path . --quit-after 120 res://tests/melee_probe.tscn

func _ready() -> void:
	var floor_sb := StaticBody3D.new(); floor_sb.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(40, 1, 40)
	cs.shape = bs; cs.position = Vector3(0, -0.5, 0); floor_sb.add_child(cs); add_child(floor_sb)

	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	# Player faces -Z by default; melee cone points that way.
	await get_tree().physics_frame
	await get_tree().physics_frame

	# front (in cone, in range), front-side (in cone), behind (out of cone), far (out of range)
	var spots := {
		"front": Vector3(0, 0.5, -2.4),
		"side":  Vector3(1.4, 0.5, -2.0),
		"behind": Vector3(0, 0.5, 2.5),
		"far": Vector3(0, 0.5, -7.0),
	}
	var enemies := {}
	for k in spots:
		var e: Node3D = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
		add_child(e); e.global_position = spots[k]
		if e.has_method("set_physics_process"): e.set_physics_process(false)
		enemies[k] = e
	await get_tree().physics_frame
	var hp0 := {}
	for k in enemies:
		hp0[k] = (enemies[k].get_node("Damageable") as Damageable).current_health

	player._do_melee()
	await get_tree().physics_frame

	for k in enemies:
		var e = enemies[k]
		var hp := (e.get_node("Damageable") as Damageable).current_health
		var dmg: float = hp0[k] - hp
		var vel: float = (e.velocity as Vector3).length() if "velocity" in e else 0.0
		print("MELEE %-7s dmg=%.0f knockback_vel=%.1f" % [k, dmg, vel])
	# Expect: front/side hit (dmg>0, knockback>0); behind/far untouched (dmg=0).
	var front_hit: bool = (float(hp0["front"]) - (enemies["front"].get_node("Damageable") as Damageable).current_health) > 0.0
	var behind_hit: bool = (float(hp0["behind"]) - (enemies["behind"].get_node("Damageable") as Damageable).current_health) > 0.0
	var far_hit: bool = (float(hp0["far"]) - (enemies["far"].get_node("Damageable") as Damageable).current_health) > 0.0
	print("MELEE ", "OK" if (front_hit and not behind_hit and not far_hit) else "FAIL")
	get_tree().quit()
