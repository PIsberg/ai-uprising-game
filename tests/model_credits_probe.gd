extends Node
## Probe: every 3D model the game ships is named in CREDITS.md (#363). Eleven
## Sketchfab models (CC-BY, one CC-BY-NC, one Sketchfab Standard) shipped with no
## credit at all; CC-BY requires one. A model whose source is not identified yet is
## still named there, under its own heading, so the gap stays visible instead of
## silent. Kenney kit pieces are credited by kit, so files from a kit folder count
## through the kit's line (KIT_DIRS).
##   godot --headless --path . --audio-driver Dummy res://tests/model_credits_probe.tscn

## Folders whose every file comes from one credited kit (the kit's CREDITS.md entry
## names the folder).
const KIT_DIRS := ["res://assets/models/weapons", "res://assets/models/suburb"]

func _scan(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".glb"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), out)

func _ready() -> void:
	var credits := FileAccess.get_file_as_string("res://CREDITS.md")
	var models: Array = []
	_scan("res://assets/models", models)
	var missing: Array = []
	for m: String in models:
		if KIT_DIRS.any(func(k: String) -> bool: return m.begins_with(k)):
			continue
		if not credits.contains(m.get_file()):
			missing.append(m.trim_prefix("res://"))
	for k: String in KIT_DIRS:
		if not credits.contains(k.trim_prefix("res://")):
			missing.append(k.trim_prefix("res://") + " (kit folder)")
	var ok := missing.is_empty() and models.size() > 30
	print("%s every shipped model is named in CREDITS.md (%d models) %s" % ["OK  " if ok else "FAIL", models.size(), missing])
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
