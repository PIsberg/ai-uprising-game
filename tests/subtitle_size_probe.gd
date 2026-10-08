extends Node
## Accessibility "Subtitle Size" (GraphicsSettings.subtitle_scale, 0.8..2.0):
## scales the timed spoken text, which disappears before a slow reader or a
## player far from the screen can make it out:
##   * cutscene subtitles (CutscenePlayer, base 26 px);
##   * overlord taunts over the HUD (base 22 px);
##   * the victory transmission body (base 22 px).
## For 1.0 and 2.0 the probe builds each real label and reads its font size,
## and at 2.0 the longest overlord taunt must still fit inside the 1920 px
## HUD (it used to be one unwrapped line). The setter clamps and persists.
## Restores the player's value.
##   godot --headless --path . --audio-driver Dummy res://tests/subtitle_size_probe.tscn

var _fail: Array[String] = []

func _check(cond: bool, label: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

static func _px(l: Label) -> int:
	return l.get_theme_font_size("font_size") if l else -1

func _sizes() -> Dictionary:
	var out := {}
	var cp := CutscenePlayer.new()
	cp.call("_build_overlay")
	out["cutscene"] = _px(cp.get("_subtitle"))
	cp.free()
	var vt := VictoryTransmission.new()
	vt.call("_build_ui")
	out["victory"] = _px(vt.get("_body"))
	vt.free()
	var hud: Node = load("res://scenes/ui/hud.tscn").instantiate()
	add_child(hud)
	await get_tree().process_frame
	var ol: Label = hud.get("_overlord_label")
	out["overlord"] = _px(ol)
	var longest := ""
	for t in hud.get("OVERLORD_TAUNTS"):
		if String(t).length() > longest.length():
			longest = String(t)
	ol.text = longest
	await get_tree().process_frame
	await get_tree().process_frame
	out["overlord_rect"] = ol.get_global_rect()
	hud.queue_free()
	await get_tree().process_frame
	return out

func _run() -> void:
	var gs := GraphicsSettings
	if not gs.has_method("set_subtitle_scale"):
		_check(false, "GraphicsSettings has set_subtitle_scale()")
		_finish()
		return
	var original: float = gs.get("subtitle_scale")

	gs.call("set_subtitle_scale", 1.0)
	var base: Dictionary = await _sizes()
	gs.call("set_subtitle_scale", 2.0)
	var big: Dictionary = await _sizes()
	for key in ["cutscene", "overlord", "victory"]:
		print("       %s: %d px at 1.0, %d px at 2.0" % [key, base[key], big[key]])
		_check(base[key] > 0 and big[key] == base[key] * 2, "%s text doubles at 2.0 (%d -> %d)" % [key, base[key], big[key]])
	var r: Rect2 = big["overlord_rect"]
	_check(r.position.x >= 0.0 and r.end.x <= 1920.0,
		"longest overlord taunt fits on screen at 2.0 (x %.0f..%.0f of 1920)" % [r.position.x, r.end.x])

	gs.call("set_subtitle_scale", 0.2)
	_check(is_equal_approx(float(gs.get("subtitle_scale")), 0.8), "clamps below to 0.8")
	gs.call("set_subtitle_scale", 9.0)
	_check(is_equal_approx(float(gs.get("subtitle_scale")), 2.0), "clamps above to 2.0")
	gs.call("set_subtitle_scale", 1.5)
	gs.set("subtitle_scale", 1.0)
	gs.call("_load_settings")
	_check(is_equal_approx(float(gs.get("subtitle_scale")), 1.5), "1.5 survives a settings reload")
	gs.call("set_subtitle_scale", original)
	_finish()

func _finish() -> void:
	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit(0 if _fail.is_empty() else 1)
