extends Node
## Probe: no text the game shows uses a glyph that renders as a colour emoji (#398).
## U+2714 ✔ and U+2716 ✖ have emoji presentation by default: in both the default
## font and Orbitron they fall back to the system emoji font and draw purple,
## ignoring the label colour (seen on the UPRISING draft, the achievements list
## and the HUD checklist). Their text forms U+2713 ✓ and U+2715 ✕ draw in the label
## colour (checked in a windowed render). Scans scripts, scenes and strings.csv.
##   godot --headless --path . --audio-driver Dummy res://tests/glyph_probe.tscn

const BANNED := {"✔": "✓", "✖": "✕"}
var hits: Array = []

func _scan(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") or f.ends_with(".tscn") or f.ends_with(".csv"):
			var path := dir.path_join(f)
			var text := FileAccess.get_file_as_string(path)
			for g in BANNED:
				if text.contains(g):
					hits.append("%s (%s, use %s)" % [path.trim_prefix("res://"), g, BANNED[g]])
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d))

func _ready() -> void:
	for root in ["res://scripts", "res://scenes", "res://assets/i18n"]:
		_scan(root)
	print("OK  " if hits.is_empty() else "FAIL", " no emoji-presentation check marks ", hits)
	print("RESULT %s" % ("PASS" if hits.is_empty() else "FAIL"))
	get_tree().quit(0 if hits.is_empty() else 1)
