extends Node3D
func _ready() -> void:
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.1,0.11,0.15)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.8,0.8,0.9); e.ambient_light_energy = 0.7
	env.environment = e; add_child(env)
	var key := DirectionalLight3D.new(); key.rotation_degrees = Vector3(-40,30,0); key.light_energy = 1.3; add_child(key)
	var body := StaticBody3D.new(); body.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(60,1,60); cs.shape = bs; cs.position = Vector3(0,-0.5,0); body.add_child(cs)
	var fmi := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(60,60); fmi.mesh = pm; body.add_child(fmi); add_child(body)
	var player := CharacterBody3D.new(); player.add_to_group("player"); player.collision_layer = 2
	var pcs := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius=0.4; cap.height=1.7; pcs.shape=cap; player.add_child(pcs)
	var pdmg := Damageable.new(); pdmg.name="Damageable"; pdmg.max_health=200.0; player.add_child(pdmg)
	add_child(player); player.global_position = Vector3(0,1.2,0)
	var st := (load("res://scenes/enemies/strider.tscn") as PackedScene).instantiate()
	st.position = Vector3(0,0.5,14); add_child(st)
	await get_tree().physics_frame
	var hp0: float = pdmg.current_health
	# Camera looking at the strider from behind the player.
	var cam := Camera3D.new(); add_child(cam); cam.fov = 50
	cam.position = Vector3(2.4,2.2,-3.0); cam.look_at(Vector3(0,1.0,14), Vector3.UP)
	await get_tree().create_timer(4.0).timeout
	# Screenshot only with a real display; --headless has no framebuffer to read.
	if DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir()+"/strider_ingame.png")
	print("PROBE player_hp_before=", hp0, " after=", pdmg.current_health, " strider_shot=", pdmg.current_health < hp0)
	get_tree().quit()
