extends Node
## Every sound id the code and data reference must resolve to a stream.
## AudioBus.synth(id) returns null for an unknown id and every play path then
## silently does nothing, so a typo'd or never-registered id is a silent event
## nobody notices (the registry already carries two such fixes: gauss_fire
## and victory_sting). Scans the sources at runtime for the ids passed as
## literals to play_synth_at / play_synth_ui / synth / play_music /
## play_ambience_layer / play_lore, the "music" keys in level_defs, and each
## weapon .tres sound_id (which weapon.gd resolves as <id>_fire; reload and
## empty fall back to the generic "reload" / "empty_click"), and asserts each
## resolves through AudioBus.synth (sample override or synth registry).
## Guards against a broken scan by requiring a healthy number of ids.
##   godot --headless --path . --audio-driver Dummy res://tests/sound_id_probe.tscn

const MIN_IDS := 40
var _fail: Array[String] = []

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail.append(label)

func _scan_dir(path: String, ext: String, out: Array[String]) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir():
			if not name.begins_with("."):
				_scan_dir(path.path_join(name), ext, out)
		elif name.ends_with(ext):
			out.append(path.path_join(name))
		name = d.get_next()
	d.list_dir_end()

func _ready() -> void:
	var ids: Dictionary = {} # id -> first source
	var scripts: Array[String] = []
	_scan_dir("res://scripts", ".gd", scripts)
	var rx_call := RegEx.new()
	rx_call.compile("(play_synth_at|play_synth_ui|synth|play_music|play_ambience_layer|play_lore)[(][ ]*\"([a-z0-9_]+)\"")
	var rx_music := RegEx.new()
	rx_music.compile("\"music\"[ ]*:[ ]*\"([a-z0-9_]+)\"")
	for f in scripts:
		var text := FileAccess.get_file_as_string(f)
		for m in rx_call.search_all(text):
			var id := m.get_string(2)
			if not ids.has(id):
				ids[id] = f.trim_prefix("res://") + " " + m.get_string(1)
		for m in rx_music.search_all(text):
			var id := m.get_string(1)
			if not ids.has(id):
				ids[id] = f.trim_prefix("res://") + " level music"
	var weapons: Array[String] = []
	_scan_dir("res://assets/weapons", ".tres", weapons)
	var rx_wid := RegEx.new()
	rx_wid.compile("sound_id[ ]*=[ ]*\"([a-z0-9_]+)\"")
	for f in weapons:
		var m := rx_wid.search(FileAccess.get_file_as_string(f))
		if m:
			var id := m.get_string(1) + "_fire"
			if not ids.has(id):
				ids[id] = f.trim_prefix("res://") + " sound_id"
	# The two generic fallbacks weapons rely on must exist too.
	ids["reload"] = "weapon.gd reload fallback"
	ids["empty_click"] = "weapon.gd empty fallback"

	print("scanned %d scripts + %d weapon resources: %d distinct sound ids" % [scripts.size(), weapons.size(), ids.size()])
	_check(ids.size() >= MIN_IDS, "scanner found at least %d ids (%d)" % [MIN_IDS, ids.size()])
	var missing: Array[String] = []
	for id in ids:
		if AudioBus.synth(id) == null:
			missing.append(id)
	missing.sort()
	for id in missing:
		print("    missing: %s   (%s)" % [id, ids[id]])
	_check(missing.is_empty(), "every referenced sound id resolves to a stream (%d missing)" % missing.size())

	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit()
