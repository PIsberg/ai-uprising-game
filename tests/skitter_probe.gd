extends Node3D
## Dev probe: drops a SKITTER swarm around a player and confirms they rush in,
## bite (player takes damage), and die cleanly.
##   godot --headless --path . res://tests/skitter_probe.tscn
func _ready() -> void:
	add_child(DirectionalLight3D.new())
	var body := StaticBody3D.new(); body.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(60,1,60); cs.shape = bs
	cs.position = Vector3(0,-0.5,0); body.add_child(cs); add_child(body)
	var player := CharacterBody3D.new(); player.add_to_group("player"); player.collision_layer = 2
	var pcs := CollisionShape3D.new(); var c := CapsuleShape3D.new(); c.radius=0.4; c.height=1.7; pcs.shape=c; player.add_child(pcs)
	var pdmg := Damageable.new(); pdmg.name="Damageable"; pdmg.max_health=200.0; player.add_child(pdmg)
	add_child(player); player.global_position = Vector3(0,1.2,0)
	var sk := []
	for i in 8:
		var s := (load("res://scenes/enemies/skitter.tscn") as PackedScene).instantiate()
		var a := TAU*i/8.0
		# Close ring so the bite fires without a baked navmesh (swarm pathing is
		# nav-verified by the real level loads above).
		s.position = Vector3(cos(a)*1.5, 0.4, sin(a)*1.5)
		add_child(s); sk.append(s)
	await get_tree().physics_frame
	var hp0: float = pdmg.current_health
	await get_tree().create_timer(4.0).timeout
	print("PROBE swarm_size=", sk.size(), " player_hp_before=", hp0, " after=", pdmg.current_health, " swarm_bit=", pdmg.current_health < hp0)
	for s in sk:
		if is_instance_valid(s): s.hp.apply_damage(999.0, player)
	await get_tree().create_timer(0.6).timeout
	var alive := 0
	for s in sk:
		if is_instance_valid(s): alive += 1
	print("PROBE alive_after_kill=", alive)
	get_tree().quit()
