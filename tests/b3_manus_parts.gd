extends Node3D
## Prints every MeshInstance3D of the manus with its world AABB (bot at origin,
## Model un-rotated) — locates the hand vs base ends numerically.
func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	_go.call_deferred()

func _go() -> void:
	var bot: Node3D = load("res://scenes/enemies/manus.tscn").instantiate()
	bot.set("preview", true)
	add_child(bot)
	bot.global_position = Vector3.ZERO
	for f in 10:
		await get_tree().process_frame
	for mi in bot.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh == null:
			continue
		var ab: AABB = inst.global_transform * inst.mesh.get_aabb()
		print("PART %-14s parent=%-12s center=%v size=%v" \
			% [inst.name, inst.get_parent().name, ab.get_center(), ab.size])
	print("PARTS DONE")
	get_tree().quit()
