extends Node3D
## Dev probe: a GUNNER suppresses a player at range; confirms the spin-up burst
## connects (player takes damage) and it dies cleanly.
##   godot --headless --path . res://tests/gunner_probe.tscn
func _ready() -> void:
	add_child(DirectionalLight3D.new())
	var sb := StaticBody3D.new(); sb.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(80,1,80); cs.shape = bs; cs.position = Vector3(0,-0.5,0); sb.add_child(cs); add_child(sb)
	var player := CharacterBody3D.new(); player.add_to_group("player"); player.collision_layer = 2
	var pcs := CollisionShape3D.new(); var c := CapsuleShape3D.new(); c.radius=0.4; c.height=1.7; pcs.shape=c; player.add_child(pcs)
	var pdmg := Damageable.new(); pdmg.name="Damageable"; pdmg.max_health=400.0; player.add_child(pdmg)
	add_child(player); player.global_position = Vector3(0,1.2,0)
	var g := (load("res://scenes/enemies/gunner.tscn") as PackedScene).instantiate()
	g.position = Vector3(0,0.5,22); add_child(g)
	await get_tree().physics_frame
	var hp0: float = pdmg.current_health
	await get_tree().create_timer(6.0).timeout
	print("PROBE hp_before=", hp0, " after=", pdmg.current_health, " suppressed=", pdmg.current_health < hp0)
	if is_instance_valid(g): g.hp.apply_damage(9999.0, player)
	await get_tree().create_timer(0.5).timeout
	print("PROBE gunner_dead=", not is_instance_valid(g) or g.state == 6)
	get_tree().quit()
