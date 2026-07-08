extends SceneTree
func _init() -> void:
	await process_frame
	var gs := root.get_node("/root/GameState")
	print("max_level_reached=%d (0-based)" % gs.max_level_reached)
	var camp: Array = gs.CAMPAIGN
	for i in camp.size():
		var id: String = gs.level_id_from_path(camp[i])
		var def = LevelDefs.get_def(id)
		var nm = def.get("name", id)
		var boss = LevelDefs.level_is_boss(id)
		var obj = def.get("objective", "")
		print("%2d %-14s %-26s %s | %s" % [i, id, nm, ("[BOSS]" if boss else "      "), obj])
	quit()
