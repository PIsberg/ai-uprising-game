extends Node
## Probe: every 3D model the game ships is named in CREDITS.md (#363). Eleven
## Sketchfab models (CC-BY, one CC-BY-NC since replaced (#406), one Sketchfab
## Standard) shipped with no credit at all; CC-BY requires one. Naming a model is not enough: the WAR-BOT's
## was named for months under a "source is not identified yet" heading, which passed
## this probe while shipping a model with no known licence (#435, found in the end:
## CC0). So a file under any heading with UNSOURCED_MARK in it fails too: a model
## with no source does not ship. The end credits (credits.gd LINES) are a hand-kept
## summary of the same file, and three CC-BY artists were missing from them, so every
## artist CREDITS.md credits under a CC-BY licence must be named in the crawl too.
## Kenney kit pieces are credited by kit, so files from a kit folder count
## through the kit's line (KIT_DIRS).
##   godot --headless --path . --audio-driver Dummy res://tests/model_credits_probe.tscn

## Folders whose every file comes from one credited kit (the kit's CREDITS.md entry
## names the folder).
const KIT_DIRS := ["res://assets/models/weapons", "res://assets/models/suburb"]
## A CREDITS.md heading holding this marks its section as models with no source.
const UNSOURCED_MARK := "not identified"

## The artists CREDITS.md credits on a line that carries a CC-BY licence: the name in
## the first `by **Name**`, without a bracketed handle.
static func cc_by_artists(credits: String) -> Array:
	var out: Array = []
	var by := RegEx.create_from_string("by [*][*]([^*(]+)")
	for line: String in credits.split("\n"):
		if not line.contains("CC-BY"):
			continue
		var m := by.search(line)
		if m != null:
			out.append(m.get_string(1).strip_edges())
	return out

## The .glb files CREDITS.md names under a heading that says their source is unknown.
static func unsourced(credits: String) -> Array:
	var out: Array = []
	var open := false
	var glb := RegEx.create_from_string("[A-Za-z0-9_.-]+[.]glb")
	for line: String in credits.split("\n"):
		if line.begins_with("#"):
			open = line.to_lower().contains(UNSOURCED_MARK)
		elif open:
			for m: RegExMatch in glb.search_all(line):
				out.append(m.get_string())
	return out

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
	var named := missing.is_empty() and models.size() > 30
	print("%s every shipped model is named in CREDITS.md (%d models) %s" % ["OK  " if named else "FAIL", models.size(), missing])
	# The parser must see a gap when there is one, or the check below is vacuous.
	var sample: Array = unsourced("### Robots\n`a.glb`\n### Source not identified yet\n`b.glb` and `c-d.glb`\n## Fonts\n`e.glb`\n")
	var parses := sample == ["b.glb", "c-d.glb"]
	print("%s a model under a 'not identified' heading is found %s" % ["OK  " if parses else "FAIL", sample])
	var gaps: Array = unsourced(credits)
	var sourced := gaps.is_empty()
	print("%s no shipped model is listed without a source %s" % ["OK  " if sourced else "FAIL", gaps])
	var crawl := ""
	for e: Dictionary in load("res://scripts/ui/credits.gd").LINES:
		crawl += str(e["text"]) + "\n"
	var artists: Array = cc_by_artists(credits)
	var uncrawled: Array = artists.filter(func(a: String) -> bool: return not crawl.contains(a))
	# 13 since #406: the HOWITZER's CC-BY-NC model, whose line counted here, is gone.
	var crawled := uncrawled.is_empty() and artists.size() >= 13
	print("%s every CC-BY artist is named in the end credits (%d artists) %s" % ["OK  " if crawled else "FAIL", artists.size(), uncrawled])
	var ok := named and parses and sourced and crawled
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
