extends Node
func _ready(): _run.call_deferred()
func _count_meshes(n: Node) -> int:
	var c := 0
	if n is MeshInstance3D: c += 1
	for ch in n.get_children(): c += _count_meshes(ch)
	return c
func _run():
	var fails: Array = []
	for k in LevelBuilder.PROP_SCENES:
		var inst = (LevelBuilder.PROP_SCENES[k] as PackedScene).instantiate()
		add_child(inst)
		await get_tree().process_frame
		var meshes := _count_meshes(inst)
		if meshes == 0:
			fails.append("%s(0mesh)" % k)
		inst.queue_free()
	print("PROPS ", "PASS" if fails.is_empty() else "FAIL " + str(fails), " count=", LevelBuilder.PROP_SCENES.size())
	get_tree().quit()
