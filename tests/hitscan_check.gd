extends Node3D
## Headless check: does the player's hitscan ray fly downrange, or hit something
## right in front of the camera? Sets up the real player + a target wall 20m
## ahead and replicates weapon.gd's exact ray.
##   godot --headless --path . tests/hitscan_check.tscn

func _ready() -> void:
	# Floor (world layer 1).
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new(); fbox.size = Vector3(80, 1, 80)
	fcs.shape = fbox; fcs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fcs); add_child(floor_body)

	# Target wall 20m ahead (-Z), world layer 1.
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var wcs := CollisionShape3D.new()
	var wbox := BoxShape3D.new(); wbox.size = Vector3(8, 4, 0.5)
	wcs.shape = wbox
	wall.add_child(wcs); add_child(wall)
	wall.global_position = Vector3(0, 1.6, -20)

	# Real player.
	var player: Node3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var cam := player.find_child("Camera3D", true, false) as Camera3D
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z
	print("camera at ", origin, " facing ", dir)

	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 60.0)
	q.collision_mask = 0b0000101 # world + enemy, exactly as weapon.gd
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		print("RESULT: ray hit nothing (flies full 60m) — clear")
	else:
		var d := origin.distance_to(hit.position)
		print("RESULT: hit ", hit.collider, " at ", hit.position, " dist=", d,
			"  (expected ~", origin.distance_to(Vector3(0,1.6,-20)), " = the wall)")
	# Also report whether excluding the player even matters (does the ray hit the
	# player body when NOT excluded?).
	var q2 := PhysicsRayQueryParameters3D.create(origin, origin + dir * 2.0)
	q2.collision_mask = 0b0000101
	var near := space.intersect_ray(q2)
	print("near 2m (no exclude): ", ("nothing" if near.is_empty() else near.collider))
	get_tree().quit()
