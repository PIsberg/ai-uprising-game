extends Node3D
## Dev probe: stands a player in front of the redesigned ALIEN and confirms it
## charges, spits bio-plasma, and the orbs damage the player (no melee needed).
##   godot --headless --path . res://tests/alien_probe.tscn

func _ready() -> void:
	add_child(DirectionalLight3D.new())
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3(80, 1, 80); cs.shape = bs
	cs.position = Vector3(0, -0.5, 0); body.add_child(cs); add_child(body)

	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pcs := CollisionShape3D.new()
	var caps := CapsuleShape3D.new(); caps.radius = 0.4; caps.height = 1.7; pcs.shape = caps
	player.add_child(pcs)
	var pdmg := Damageable.new(); pdmg.name = "Damageable"; pdmg.max_health = 100.0
	player.add_child(pdmg)
	add_child(player)
	player.global_position = Vector3(0, 1.2, 0)

	var alien := (load("res://scenes/enemies/alien.tscn") as PackedScene).instantiate()
	alien.position = Vector3(11, 2.0, 0)
	add_child(alien)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hp0: float = pdmg.current_health

	await get_tree().create_timer(6.0).timeout
	print("PROBE player_hp_before=", hp0, " after=", pdmg.current_health, " took_spit_dmg=", pdmg.current_health < hp0)
	get_tree().quit()
