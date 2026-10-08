extends Node
## Colourblind correction (accessibility): Settings offers Off / Protanopia /
## Deuteranopia / Tritanopia, and the world post-process multiplies every pixel
## by one 3x3 daltonize matrix that GraphicsSettings builds for the mode.
##
## The probe tests the matrix the GPU receives, against its OWN reference
## simulation of each deficiency (Machado, Oliveira & Fernandes 2009, severity
## 1.0, the matrices below), so it does not share math with the code under test:
##   * for a colour pair that deficiency confuses, the pair seen through the
##     simulated eye is at least MIN_GAIN times further apart after correction;
##   * Off is the identity (no change for everyone else);
##   * greys are fixed points of every mode, so white and grey menu text keeps
##     its colour while the overlay tints only what a deficiency confuses;
##   * ONE correction covers every screen: a GraphicsSettings overlay sits above
##     every CanvasLayer the game draws (the level HUD, cutscenes, the campaign
##     map, the Armory at layer 60), carries the matrix, and is hidden when Off;
##   * the player's own post-process no longer applies it (no double correction);
##   * the choice persists through settings.cfg (the probe restores the original).
##   godot --headless --path . --audio-driver Dummy res://tests/colorblind_probe.tscn

const MIN_GAIN := 1.25

## Simulation matrices (rows = output R, G, B), linear RGB.
const SIM := {
	1: [Vector3(0.152286, 1.052583, -0.204868), Vector3(0.114503, 0.786281, 0.099216), Vector3(-0.003882, -0.048116, 1.051998)],
	2: [Vector3(0.367322, 0.860646, -0.227968), Vector3(0.280085, 0.672501, 0.047413), Vector3(-0.011820, 0.042940, 0.968881)],
	3: [Vector3(1.255528, -0.076749, -0.178779), Vector3(-0.078411, 0.930809, 0.147602), Vector3(0.004733, 0.691367, 0.303900)],
}
## A pair each deficiency confuses: red vs green for protan/deutan (enemy-red
## telegraphs against green hazards), blue vs green for tritan.
const PAIRS := {
	1: [Vector3(0.85, 0.15, 0.1), Vector3(0.25, 0.65, 0.1)],
	2: [Vector3(0.85, 0.15, 0.1), Vector3(0.25, 0.65, 0.1)],
	3: [Vector3(0.1, 0.35, 0.9), Vector3(0.1, 0.75, 0.45)],
}
const NAMES := {1: "protanopia", 2: "deuteranopia", 3: "tritanopia"}

var _fail: Array[String] = []

func _check(cond: bool, label: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

static func _apply_rows(rows: Array, c: Vector3) -> Vector3:
	return Vector3(rows[0].dot(c), rows[1].dot(c), rows[2].dot(c))

static func _apply_basis(b: Basis, c: Vector3) -> Vector3:
	# The shader computes `cb_matrix * col`; a Basis uploads as that mat3.
	return b * c

func _run() -> void:
	var gs := GraphicsSettings
	if not gs.has_method("colorblind_matrix") or not gs.has_method("set_colorblind_mode"):
		_check(false, "GraphicsSettings has colorblind_matrix() and set_colorblind_mode()")
		_finish()
		return
	var original: int = int(gs.get("colorblind_mode"))
	_check(gs.get("COLORBLIND_LABELS") is Array and (gs.get("COLORBLIND_LABELS") as Array).size() == 4,
		"four modes offered (Off + three deficiencies)")

	var off: Basis = gs.call("colorblind_matrix", 0)
	_check(off.is_equal_approx(Basis.IDENTITY), "Off is the identity")

	for mode in [1, 2, 3]:
		var m: Basis = gs.call("colorblind_matrix", mode)
		var a: Vector3 = PAIRS[mode][0]
		var b: Vector3 = PAIRS[mode][1]
		var before := _apply_rows(SIM[mode], a).distance_to(_apply_rows(SIM[mode], b))
		var after := _apply_rows(SIM[mode], _apply_basis(m, a)).distance_to(_apply_rows(SIM[mode], _apply_basis(m, b)))
		_check(after >= before * MIN_GAIN,
			"%s: confusable pair %.3f apart as seen, %.3f after correction (x%.2f, need x%.2f)"
			% [NAMES[mode], before, after, after / maxf(before, 0.0001), MIN_GAIN])

	for mode in [1, 2, 3]:
		var m: Basis = gs.call("colorblind_matrix", mode)
		var worst := 0.0
		for g in [0.0, 0.2, 0.5, 0.85, 1.0]:
			worst = maxf(worst, (_apply_basis(m, Vector3(g, g, g)) - Vector3(g, g, g)).length())
		_check(worst < 0.01, "%s leaves greys and white unchanged (max shift %.4f)" % [NAMES[mode], worst])

	# Every screen the game draws, alive at once: a level player (post layer +
	# HUD), the campaign map, the Armory.
	var player: Node = load("res://scenes/player/player.tscn").instantiate()
	add_child(player)
	add_child(load("res://scenes/ui/campaign_map.tscn").instantiate())
	add_child(Armory.new())
	await get_tree().process_frame
	await get_tree().process_frame

	gs.call("set_colorblind_mode", 2)
	await get_tree().process_frame
	var cb: CanvasLayer = gs.get_node_or_null("ColorblindOverlay") as CanvasLayer
	_check(cb != null, "GraphicsSettings owns a ColorblindOverlay CanvasLayer")
	if cb:
		var top := -1000000
		var top_name := ""
		for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
			if n != cb and (n as CanvasLayer).layer > top:
				top = (n as CanvasLayer).layer
				top_name = str(n.get_path())
		_check(cb.layer > top, "overlay layer %d is above every other CanvasLayer (highest %d, %s)" % [cb.layer, top, top_name])
		_check(cb.visible, "overlay is shown for Deuteranopia")
		var rect := cb.get_node_or_null("Correct") as CanvasItem
		var csm: ShaderMaterial = rect.material as ShaderMaterial if rect else null
		var live = csm.get_shader_parameter("cb_matrix") if csm else null
		_check(live is Basis and (live as Basis).is_equal_approx(gs.call("colorblind_matrix", 2)),
			"Deuteranopia reaches the overlay's cb_matrix")
		_check(rect is Control and (rect as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"overlay never eats menu clicks")
		gs.call("set_colorblind_mode", 0)
		await get_tree().process_frame
		_check(not cb.visible, "Off hides the overlay (no extra full-screen pass)")

	var post = player.get("_post_overlay")
	var sm: ShaderMaterial = post.material if post else null
	if sm:
		gs.call("set_colorblind_mode", 2)
		var p = sm.get_shader_parameter("cb_matrix")
		_check(p == null or (p is Basis and (p as Basis).is_equal_approx(Basis.IDENTITY)),
			"the player's post-process does not correct a second time")
		gs.call("set_colorblind_mode", 0)

	# Persistence through settings.cfg.
	gs.call("set_colorblind_mode", 3)
	gs.set("colorblind_mode", 0)
	gs.call("_load_settings")
	_check(int(gs.get("colorblind_mode")) == 3, "Tritanopia survives a settings reload (got %d)" % int(gs.get("colorblind_mode")))
	gs.call("set_colorblind_mode", original)
	_finish()

func _finish() -> void:
	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit(0 if _fail.is_empty() else 1)
