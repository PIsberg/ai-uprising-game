extends Node
## Every `Autoload.method(` call in the project resolves to a real method on that
## autoload. Guards the squash-merge failure class seen twice on main in one week:
## #87's squash deleted GraphicsSettings.flash_energy() and #92's deleted
## GameState.peek_save() while their callers stayed, so every shot (and every
## menu boot with a save) script-errored and nothing in the suite noticed.
## Static scan: reads project.godot's [autoload] table, walks every .gd under
## res://scripts, res://scenes and res://tests, and asserts has_method() on the
## live singleton for each `<Autoload>.<name>(` it finds. Property access and
## signal connects (`GameState.hud.x(`, `GameState.sig.connect(`) don't match.
##   godot --headless --path . --audio-driver Dummy res://tests/autoload_api_probe.tscn

const SCAN_ROOTS := ["res://scripts", "res://scenes", "res://tests"]

var _fail: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var autoloads := _autoload_names()
	print("autoloads: ", autoloads)
	var pattern := RegEx.new()
	pattern.compile("\\b(" + "|".join(autoloads) + ")\\.([A-Za-z_][A-Za-z_0-9]*)\\(")
	var files: Array[String] = []
	for root in SCAN_ROOTS:
		_collect_gd(root, files)
	var checked := 0
	var seen := {}
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for m in pattern.search_all(text):
			var who: String = m.get_string(1)
			var fn: String = m.get_string(2)
			var key := who + "." + fn
			if seen.has(key):
				continue
			seen[key] = true
			checked += 1
			var node := get_node_or_null("/root/" + who)
			if node == null:
				_fail.append("%s: autoload node missing" % who)
				continue
			if not node.has_method(fn):
				_fail.append("%s.%s() called in %s but not defined on %s" % [who, fn, path, (node.get_script() as Script).resource_path])
	print("scanned %d files, %d distinct autoload calls" % [files.size(), checked])
	for f in _fail:
		print("  FAIL ", f)
	if checked < 50:
		_fail.append("only %d calls found: the scan itself is broken" % checked)
	print("RESULT %s" % ("PASS" if _fail.is_empty() else "FAIL"))
	get_tree().quit(0 if _fail.is_empty() else 1)

func _autoload_names() -> PackedStringArray:
	var names := PackedStringArray()
	var cfg := ConfigFile.new()
	if cfg.load("res://project.godot") == OK and cfg.has_section("autoload"):
		for k in cfg.get_section_keys("autoload"):
			names.append(k)
	return names

func _collect_gd(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var p := dir_path.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				_collect_gd(p, out)
		elif name.ends_with(".gd"):
			out.append(p)
		name = d.get_next()
	d.list_dir_end()
