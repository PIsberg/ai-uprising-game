extends Node3D
## Dev probe: launches a swarm missile straight ahead while an enemy sits off to
## the side, and confirms the homing steers it into the target (enemy takes
## damage). Headless-friendly (no rendering needed).
##   godot --headless --path . res://tests/swarm_probe.tscn

func _ready() -> void:
	add_child(DirectionalLight3D.new())
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80, 1, 80)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)

	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pcs := CollisionShape3D.new()
	pcs.shape = CapsuleShape3D.new()
	player.add_child(pcs)
	add_child(player)
	player.global_position = Vector3(0, 1.6, 30)

	var enemy := (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	enemy.position = Vector3(7, 0.5, -12)   # well off the firing axis
	add_child(enemy)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hp0: float = enemy.hp.current_health

	var proj = (load("res://scenes/weapons/projectile_swarm.tscn") as PackedScene).instantiate()
	add_child(proj)
	proj.global_position = Vector3(0, 1.2, 0)
	# Fire straight down -Z; the target is +7 X and -12 Z, so only homing can hit it.
	proj.launch(Vector3(0, 0, -1) * 34.0, player, 22.0, 2.2, 14.0)

	await get_tree().create_timer(2.5).timeout
	var hp1: float = enemy.hp.current_health if is_instance_valid(enemy) else -999.0
	print("PROBE hp_before=", hp0, " hp_after=", hp1, " homed_and_hit=", hp1 < hp0)
	get_tree().quit()
