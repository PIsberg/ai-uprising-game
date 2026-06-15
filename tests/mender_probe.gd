extends Node3D
## Dev probe: drops a MENDER next to a wounded android and confirms it flies in
## and beam-heals it (and runs its flight/death without errors).
##   godot --headless --path . res://tests/mender_probe.tscn

func _ready() -> void:
	var key := DirectionalLight3D.new()
	add_child(key)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80, 1, 80)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)

	# Player far off so the mender doesn't flee out of the arena.
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pcs := CollisionShape3D.new()
	pcs.shape = CapsuleShape3D.new()
	player.add_child(pcs)
	add_child(player)
	player.global_position = Vector3(0, 1.6, 28)

	# A wounded android for the mender to repair.
	var ally := (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	ally.position = Vector3(0, 0.5, 0)
	add_child(ally)
	await get_tree().physics_frame
	await get_tree().physics_frame
	ally.hp.current_health = ally.hp.max_health * 0.3
	var wounded_at: float = ally.hp.current_health

	var mender := (load("res://scenes/enemies/mender.tscn") as PackedScene).instantiate()
	mender.position = Vector3(6, 0.5, 4)
	add_child(mender)

	await get_tree().create_timer(5.0).timeout
	var healed: float = ally.hp.current_health if is_instance_valid(ally) else -1.0
	print("PROBE wounded=", wounded_at, " after=", healed, " healed_up=", healed > wounded_at)

	# Kill the mender to exercise its death path.
	if is_instance_valid(mender):
		mender.hp.apply_damage(9999.0, get_tree().get_first_node_in_group("player"))
	await get_tree().create_timer(1.5).timeout
	print("PROBE mender_freed=", not is_instance_valid(mender))
	get_tree().quit()
