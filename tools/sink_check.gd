extends Node3D
## Drops each round-bodied enemy on a flat floor, lets physics settle, then
## reports the body origin and the merged visual AABB. A robot whose visual
## bottom sits well below the floor plane (y=0) renders "under the floor".
##   godot --headless --path . --quit-after 600 res://tools/sink_check.tscn

const BOTS := ["roller", "mauler", "vacuum", "skitter", "spider", "android"]

func _ready() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	body.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.position = Vector3(80, 1, 80)
	add_child(player)

	var bots: Array = []
	for i in BOTS.size():
		var b: Node = load("res://scenes/enemies/%s.tscn" % BOTS[i]).instantiate()
		add_child(b)
		b.global_position = Vector3(i * 8.0, 0.5, 0)
		bots.append(b)
	await get_tree().create_timer(1.2).timeout
	for i in bots.size():
		var b: Node3D = bots[i]
		var lo := 1e9
		var hi := -1e9
		for mi in b.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var aabb: AABB = m.global_transform * m.mesh.get_aabb()
			lo = minf(lo, aabb.position.y)
			hi = maxf(hi, aabb.end.y)
	# body origin y, visual bottom, visual top — floor plane is y=0
		print("SINK %-8s body_y=%6.2f visual=[%6.2f .. %6.2f]%s" % [
			BOTS[i], b.global_position.y, lo, hi,
			"  <-- SUNK" if lo < -0.35 else ""])
	print("SINK_CHECK_DONE")
	get_tree().quit()
