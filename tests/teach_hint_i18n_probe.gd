extends Node
## One-time coaching hints are translated (#317). GameState.teach_hint used to
## reach the HUD toast untranslated, so es/fr/de/pt players read every hint in
## English. With the locale set to German, two real hints (a trap's TEACH_TEXT
## and an elite affix hint) must reach the HUD toast as their German rows, not
## the English key. A skirmish event toast with a number in it (GRID SURGE) must
## reach the HUD in German too (#331). tools/check_strings_csv.py guards that
## every hint and every literal skirmish toast has a row.
##   godot --headless --path . --audio-driver Dummy res://tests/teach_hint_i18n_probe.tscn

var _fails: Array[String] = []

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var prev := TranslationServer.get_locale()
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	for i in 5:
		await get_tree().process_frame
	TranslationServer.set_locale("de")
	for text: String in [CrumbleTile.TEACH_TEXT, GameState.ELITE_HINTS["swift"]]:
		var want := TranslationServer.translate(text)
		_check(want != text, "German has a row for: %s" % text.left(40))
		GameState.teach_hint.emit(text)
		await get_tree().process_frame
		var shown: String = hud.get("toast").text
		_check(shown == want, "the HUD toast shows it in German (%s)" % shown.left(50))
	# A skirmish event whose description carries a number (#331): the number
	# has to be formatted into the translated text, not into the English key.
	GameState._event_grid_surge()
	await get_tree().process_frame
	var surge: String = hud.get("toast").text
	var surge_want := "%s — %s" % [TranslationServer.translate("GRID SURGE"),
		TranslationServer.translate("Local power spike: OVERLOAD charges at double rate for %d seconds.") % int(GameState.EVENT_SURGE_TIME)]
	_check(surge.ends_with(surge_want) and surge.contains("ÜBERLADUNG"),
		"the GRID SURGE toast shows in German with its seconds (%s)" % surge.left(60))
	TranslationServer.set_locale(prev)
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)
