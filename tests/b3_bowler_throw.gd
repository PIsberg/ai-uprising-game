extends Node3D
## Functional check: a STRIKER-9 with a target throws a live MOLTEN ORB that
## flies, lands, and starts hunting. Also verifies the 3-orb cap.
func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 1, 300)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position.y = -0.5
	add_child(floor_body)
	_go.call_deferred()

func _go() -> void:
	# A stand-in player the bowler can target.
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	pcs.shape = cap
	player.add_child(pcs)
	var dmg := Damageable.new()
	dmg.name = "Damageable"
	player.add_child(dmg)
	add_child(player)
	player.global_position = Vector3(0, 1.0, -18)
	var bowler: Node3D = load("res://scenes/enemies/bowler.tscn").instantiate()
	add_child(bowler)
	bowler.global_position = Vector3(0, 0.1, 0)
	for f in 20:
		await get_tree().process_frame
	bowler.set("target", player)
	for i in 5:  # ask for 5 throws — cap should hold it to 3
		bowler.call("_perform_attack")
		await get_tree().create_timer(0.3).timeout
	await get_tree().create_timer(1.2).timeout
	var orbs := []
	for c in get_children():
		if c is EnemyOrb:
			orbs.append(c)
	print("ORBS SPAWNED: ", orbs.size(), " (cap 3)")
	for o in orbs:
		print("  orb pos=%v state=%d" % [(o as Node3D).global_position, o.get("state")])
	print("BOWLER THROW DONE")
	get_tree().quit()
