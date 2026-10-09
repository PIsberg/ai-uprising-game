extends Node
## Every task, wave, flood alert, firewall and terrain label a campaign level def shows is
## translated in each shipped language: tr() under es/fr/de/pt must return
## something other than the English key. tr() hands the key back unchanged when
## a row is missing (or when an unquoted comma split the row), so a gap reads as
## English mid-mission and nothing else fails. 64 of 78 def labels were missing
## on 2026-10-04 (#116). tools/check_strings_csv.py guards the CSV text in CI;
## this checks what Godot actually imported from it.
##   godot --headless --path . --audio-driver Dummy res://tests/i18n_label_probe.tscn

const LANGS := ["es", "fr", "de", "pt"]

var _ok := true

func _ready() -> void:
	_run.call_deferred()

func _labels() -> Dictionary:
	var out := {}
	for path: String in GameState.CAMPAIGN:
		var id := path.get_file().get_basename().trim_prefix("level_")
		var def: Dictionary = LevelDefs.get_def(id)
		for t: Dictionary in def.get("tasks", []):
			if t.get("label", "") != "":
				out[t["label"]] = id
			for w in t.get("waves", []):
				if w is Dictionary and w.get("label", "") != "":
					out[w["label"]] = id
				# A flood's or weather shift's HUD alerts (skirmish toast, tr()'d).
				if w is Dictionary:
					for key in ["flood", "weather"]:
						for k in ["warn_title", "warn_text", "drain_title", "drain_text", "clear_title", "clear_text"]:
							var s: String = (w.get(key, {}) as Dictionary).get(k, "")
							if s != "":
								out[s] = id
		for fw in def.get("firewalls", []):
			if fw is Dictionary and fw.get("label", "") != "":
				out[fw["label"]] = id
		# The campaign map's terrain warning (DEEP WATER / MOLTEN LAVA).
		var hz: Dictionary = LevelDefs.level_hazard(id)
		if hz.get("label", "") != "":
			out[hz["label"]] = id
	return out

func _run() -> void:
	var labels := _labels()
	var prev := TranslationServer.get_locale()
	# Control: a key that has had a row since the first localization commit.
	TranslationServer.set_locale("de")
	var control := tr("Eliminate all hostiles")
	print("control de: %s" % control)
	if control == "Eliminate all hostiles":
		_ok = false
		print("BAD  control: translations are not loaded at all")
	var missing := 0
	for lang in LANGS:
		TranslationServer.set_locale(lang)
		for label: String in labels:
			if tr(label) == label:
				missing += 1
				_ok = false
				print("BAD  %s untranslated: %s (%s)" % [lang, label, labels[label]])
	TranslationServer.set_locale(prev)
	print("%d labels x %d languages, %d untranslated" % [labels.size(), LANGS.size(), missing])
	_ok = _ok and labels.size() > 40 # the census itself must have found the labels
	print("RESULT ", "PASS" if _ok else "FAIL")
	get_tree().quit()
