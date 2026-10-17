extends Node
## Probe: the story reaches the screen translated (#236). With the locale set
## to German, every place the campaign's red thread is shown must show German:
## (1) the comic briefing's tagline, act header ("AKT V · DIE RELAISKETTE"),
##     trace log and trace card header;
## (2) the SECTOR CLEARED lead line;
## (3) an act's overlord line and an ambient taunt in the HUD;
## (4) the credits' 03:14 trace recap.
## What a Label shows is its text through atr() (auto-translate), so that is
## what is compared. tools/check_strings_csv.py guards that every story string
## has a row; this probe guards the display paths, three of which build their
## text with % and so never matched a row.
##   godot --headless --path . --audio-driver Dummy res://tests/story_i18n_probe.tscn

const BRIEFING := "res://scenes/cutscene/level_comic_briefing.tscn"

var _fails: Array[String] = []

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	_run.call_deferred()

func _de(s: String) -> String:
	return TranslationServer.translate(s)

## What every Label under `root` displays.
func _shown(root: Node) -> Array:
	var out: Array = []
	for lbl in root.find_children("*", "Label", true, false):
		out.append((lbl as Label).atr((lbl as Label).text))
	return out

func _run() -> void:
	var prev := TranslationServer.get_locale()
	var prev_path := GameState.current_level_path
	TranslationServer.set_locale("de")
	var campaign: Array = GameState.CAMPAIGN

	# 1. The briefing.
	GameState.pending_patch_notes = []
	GameState.current_level_path = "res://scenes/levels/level_guardrails.tscn"
	var briefing: Node = load(BRIEFING).instantiate()
	get_tree().root.add_child(briefing)
	for i in 10:
		await get_tree().process_frame
	var shown := _shown(briefing)
	var beat := StoryArc.beat("guardrails")
	var idx := campaign.find("res://scenes/levels/level_guardrails.tscn")
	for want: String in [_de(String(beat["tagline"])), "AKT V · DIE RELAISKETTE", _de(String(beat["trace"])),
			"◆ DIE 03:14-SPUR · LOG %d/%d" % [idx + 1, campaign.size()]]:
		_check(shown.has(want), "briefing shows: %s" % want.left(60))
	_check(_de(String(beat["tagline"])) != String(beat["tagline"]), "the tagline has a German row")
	briefing.queue_free()
	await get_tree().process_frame

	# 2-3. The HUD.
	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	get_tree().root.add_child(hud)
	await get_tree().process_frame
	GameState.current_level_path = "res://scenes/levels/level_gpt.tscn"
	hud.call("_update_lead_block")
	var lead_lbl: Label = hud.get("_lead_label")
	var lead_want := "◆ SPUR: " + _de(StoryArc.lead("gpt"))
	_check(lead_lbl != null and lead_lbl.atr(lead_lbl.text) == lead_want,
		"lead line: %s" % (lead_lbl.atr(lead_lbl.text) if lead_lbl else "<none>").left(70))
	var callouts_were: bool = GraphicsSettings.combat_callouts_enabled
	GraphicsSettings.combat_callouts_enabled = true
	var overlord_lbl: Label = hud.get("_overlord_label")
	for line: String in [String(StoryArc.OVERLORD_LINES[2][0]), String(hud.get("OVERLORD_TAUNTS")[0])]:
		hud.call("_overlord_say", line)
		var said := overlord_lbl.atr(overlord_lbl.text) if overlord_lbl else "<none>"
		_check(overlord_lbl != null and said == "▌ " + _de(line) and _de(line) != line,
			"overlord says it in German: %s" % said.left(60))
	GraphicsSettings.combat_callouts_enabled = callouts_were
	hud.queue_free()

	# 4. The credits.
	var credits: Node = load("res://scenes/ui/credits.tscn").instantiate()
	get_tree().root.add_child(credits)
	await get_tree().process_frame
	shown = _shown(credits)
	var last := "%02d  %s" % [campaign.size(), _de(StoryArc.lead("archon"))]
	_check(shown.has("DIE 03:14-SPUR"), "credits title in German")
	_check(shown.has(last), "credits recap in German: %s" % last.left(60))
	credits.queue_free()

	TranslationServer.set_locale(prev)
	GameState.current_level_path = prev_path
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)
