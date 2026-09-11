extends Node
## Every tr("...") literal in scripts/ must resolve in EVERY shipped locale.
## Scans the .gd sources at runtime for tr("literal") calls, then asks the
## TranslationServer (the imported .translation resources — the ground truth the
## build actually ships, not the CSV) for each key in each locale. A key with no
## message in a locale would fall back to English on that player's screen.
## Guards itself against a broken scan: it must find a healthy number of keys
## or the pass would be vacuous.
##   godot --headless --path . --audio-driver Dummy res://tests/i18n_coverage_probe.tscn

const MIN_KEYS := 60 ## fewer than this and the scanner itself is broken
var _fail: Array[String] = []

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail.append(label)

func _scan_dir(path: String, out: Array[String]) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir():
			if not name.begins_with("."):
				_scan_dir(path.path_join(name), out)
		elif name.ends_with(".gd"):
			out.append(path.path_join(name))
		name = d.get_next()
	d.list_dir_end()

func _ready() -> void:
	var files: Array[String] = []
	_scan_dir("res://scripts", files)
	var rx := RegEx.new()
	# tr("literal") with a string literal as the sole argument.
	rx.compile("\\btr\\(\\s*\"([^\"]*)\"\\s*\\)")
	var keys: Dictionary = {} # key -> first file that uses it
	for f in files:
		var text := FileAccess.get_file_as_string(f)
		for m in rx.search_all(text):
			var k := m.get_string(1)
			if not keys.has(k):
				keys[k] = f
	print("scanned %d scripts, %d distinct tr() literals" % [files.size(), keys.size()])
	_check(keys.size() >= MIN_KEYS, "scanner found at least %d keys (%d)" % [MIN_KEYS, keys.size()])

	var locales: Array = []
	for entry in GraphicsSettings.LANGUAGES:
		locales.append(String(entry[0]))
	_check(locales.size() >= 5, "at least 5 shipped locales (%d)" % locales.size())
	for loc in locales:
		var tr_obj := TranslationServer.get_translation_object(loc)
		if tr_obj == null:
			_check(false, "locale %s has an imported translation" % loc)
			continue
		var missing: Array[String] = []
		for k in keys:
			if String(tr_obj.get_message(k)).is_empty():
				missing.append(k)
		missing.sort()
		for k in missing:
			print("    %s: missing  %s   (%s)" % [loc, k, String(keys[k]).trim_prefix("res://scripts/")])
		_check(missing.is_empty(), "locale %s translates every tr() literal (%d missing)" % [loc, missing.size()])

	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit()
