extends Node
func _ready(): _run.call_deferred()
func _run():
	var fails: Array = []
	var camp: Array = []
	for p in GameState.CAMPAIGN:
		var id := GameState.level_id_from_path(p)
		camp.append(id)
		if LevelDefs.chapter_index_of(id) < 0:
			fails.append("nochapter:" + id)
	var flat: Array = []
	for c in LevelDefs.CHAPTERS:
		for id in c["ids"]: flat.append(id)
		var last: String = c["ids"][c["ids"].size() - 1]
		if not LevelDefs.level_is_boss(last):
			fails.append("end_not_boss:" + String(c["name"]))
	if flat != camp:
		fails.append("order_mismatch")
	for c in LevelDefs.CHAPTERS:
		var last: String = c["ids"][c["ids"].size() - 1]
		print("  ", c["name"], "  ends on ", LevelDefs.level_title(last))
	print("CHAPTERS ", "PASS" if fails.is_empty() else "FAIL " + str(fails))
	get_tree().quit()
