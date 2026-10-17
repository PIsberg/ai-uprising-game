extends Node
## Probe: the game-over screen is translated (#337). Its overlord taunt, the
## "Taken down by" recap and the tip were built with % around English text, so
## no translation row could match and es/fr/de/pt players read them in English.
## With the locale set to German and a DOG as the killer, the taunt, the recap
## and the dog tip on the filled death panel, and its restart button, must all
## display German.
##   godot --headless --path . --audio-driver Dummy res://tests/death_screen_i18n_probe.tscn

var _fails: Array[String] = []

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var prev := TranslationServer.get_locale()
	var prev_killer := GameState.last_killer
	TranslationServer.set_locale("de")
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	for i in 3:
		await get_tree().process_frame
	GameState.last_killer = "K-9 DOG"
	hud.call("_fill_death_recap")
	var taunt: Label = hud.get("_taunt_label")
	var recap: Label = hud.get("_recap_label")
	var tip: Label = hud.get("_tip_label")
	var shown_taunt := taunt.atr(taunt.text) if taunt else ""
	var taunts: Array = hud.get("DEATH_TAUNTS")
	var german := false
	for t: String in taunts:
		if shown_taunt == "„%s“" % TranslationServer.translate(t) and TranslationServer.translate(t) != t:
			german = true
	_check(german, "the taunt is German: %s" % shown_taunt.left(60))
	var shown_recap := recap.atr(recap.text) if recap else ""
	_check(shown_recap.begins_with("Erledigt von K-9 DOG") and shown_recap.contains("Abschüsse"),
		"the recap is German: %s" % shown_recap.left(60))
	var shown_tip := tip.atr(tip.text) if tip else ""
	_check(shown_tip.begins_with("TIPP: ") and shown_tip.contains("weich seitlich aus"),
		"the dog tip is German: %s" % shown_tip.left(60))
	var btn: Button = hud.get("game_over_restart_btn")
	var shown_btn := btn.atr(btn.text) if btn else ""
	_check(shown_btn.ends_with("(LEERTASTE)"), "the restart button is German: %s" % shown_btn)
	hud.queue_free()
	GameState.last_killer = prev_killer
	TranslationServer.set_locale(prev)
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)
