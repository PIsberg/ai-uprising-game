extends Node
## Every player setting survives a restart. GraphicsSettings saves in
## _save_settings and loads in _load_settings, two hand-kept lists; a setting
## added to one and not the other silently resets on every launch (subtitle
## size, colourblind mode and the rest each had to remember both).
##
## The probe enumerates the autoload's script variables instead of a list:
## it moves every public one to a different value that is still in range,
## saves, puts the old values back in memory, loads, and requires each to come
## back as the moved value. Runtime-only state must be named in TRANSIENT with
## the reason, so a new setting cannot be left out by accident. The player's
## settings.cfg is restored byte for byte.
##   godot --headless --path . --audio-driver Dummy res://tests/settings_roundtrip_probe.tscn

const TRANSIENT := {
	"needs_auto_quality": "derived on boot: true only when settings.cfg has no quality key",
}

var _fail: Array[String] = []

func _check(cond: bool, label: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

static func _moved(v: Variant) -> Variant:
	match typeof(v):
		TYPE_BOOL:
			return not v
		TYPE_INT:
			return v - 1 if v > 0 else v + 1
		TYPE_FLOAT:
			return v - 0.1 if v > 0.5 else v + 0.1
		TYPE_STRING:
			return "de" if v != "de" else "fr"
		TYPE_DICTIONARY:
			return {"probe_action": [1, 2]}
	return null

func _run() -> void:
	var gs := GraphicsSettings
	var path := "user://settings.cfg"
	var had_file := FileAccess.file_exists(path)
	var backup := FileAccess.get_file_as_bytes(path) if had_file else PackedByteArray()

	var original := {}
	var moved := {}
	for p in gs.get_property_list():
		if not (p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = p["name"]
		if n.begins_with("_") or TRANSIENT.has(n):
			continue
		var m = _moved(gs.get(n))
		if m == null:
			_check(false, "%s: the probe does not know how to move a %s" % [n, type_string(typeof(gs.get(n)))])
			continue
		original[n] = gs.get(n)
		moved[n] = m
	print("       %d settings, %d transient" % [moved.size(), TRANSIENT.size()])

	for n in moved:
		gs.set(n, moved[n])
	gs.call("_save_settings")
	for n in original:
		gs.set(n, original[n])
	gs.call("_load_settings")
	var lost: Array[String] = []
	for n in moved:
		var got = gs.get(n)
		var ok: bool = is_equal_approx(got, moved[n]) if typeof(got) == TYPE_FLOAT else got == moved[n]
		if not ok:
			lost.append("%s (saved %s, loaded %s)" % [n, moved[n], got])
	_check(lost.is_empty(), "all %d settings come back after save + load%s" % [moved.size(), "" if lost.is_empty() else ": lost " + ", ".join(lost)])
	_check(moved.size() >= 30, "covered %d settings (30 persisted keys today)" % moved.size())

	# Put the player's file and values back.
	if had_file:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for n in original:
		gs.set(n, original[n])
	if had_file:
		_check(FileAccess.get_file_as_bytes(path) == backup, "the player's settings.cfg is restored byte for byte")
	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit(0 if _fail.is_empty() else 1)
