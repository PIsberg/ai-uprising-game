extends Node3D
## Probe: a boss fight is staged as one. With the real HUD up:
## (1) every campaign boss has a name and an epithet, and the epithet
##     translates (es);
## (2) each phased boss's own `_phase()` agrees with boss_phase_marks() at
##     90 / 50 / 20 % health, so the bar's notches sit where the fight
##     really escalates;
## (3) BEHEMOTH-X's arrival raises the intro card: letterbox bars in, its
##     name and epithet on screen;
## (4) the boss bar is notched at 66 % and 33 %;
## (5) a hit leaves a damage trail on the bar that drains after a beat;
## (6) crossing 66 % stages phase II once (GameState.boss_phase_changed,
##     not final, banner "PHASE II", a shockwave ring in the world);
##     crossing 33 % stages the FINAL PHASE;
## (7) a 4 s hitch frame advances the card one 0.05 s step, not to its end.
##   godot --headless --path . --audio-driver Dummy res://tests/boss_presence_probe.tscn

const BOSSES := ["colossus", "titan", "overseer", "archon", "terminator", "manus", "smasher"]
const PHASED := ["colossus", "titan", "overseer", "archon", "manus", "smasher"]

var ok := true
var _beats: Array = []

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()

func _rings() -> int:
	var n := 0
	for c in get_tree().current_scene.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is TorusMesh:
			n += 1
	return n

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_floor()
	# (1) names and epithets, (2) phases agree with the marks.
	for id in BOSSES:
		var b: Node = (load("res://scenes/enemies/%s.tscn" % id) as PackedScene).instantiate()
		b.set("preview", true)
		add_child(b)
		await get_tree().process_frame
		var nm := String(b.get("boss_name")) if b.get("boss_name") != null else ""
		var ep := String(b.get("boss_epithet")) if b.get("boss_epithet") != null else ""
		_check("%s has a name and an epithet" % id, nm != "" and ep != "", "(%s / %s)" % [nm, ep])
		if ep != "":
			TranslationServer.set_locale("es")
			var es := tr(ep)
			TranslationServer.set_locale("en")
			_check("%s epithet translates" % id, es != ep, "(es: %s)" % es)
		if id in PHASED:
			var marks: Array = b.call("boss_phase_marks") if b.has_method("boss_phase_marks") else []
			_check("%s has phase marks" % id, marks.size() == 2, "(%s)" % [marks])
			var hp: Node = b.get_node("Damageable")
			var got := []
			for f in [0.9, 0.5, 0.2]:
				hp.set("current_health", float(hp.get("max_health")) * f)
				got.append(b.call("_phase"))
			_check("%s _phase() follows its marks" % id, got == [1, 2, 3], "(%s)" % [got])
		b.queue_free()
		await get_tree().process_frame

	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame
	var presence: Node = hud.find_child("BossPresence", true, false)
	_check("HUD carries a BossPresence", presence != null)
	if presence == null:
		print("RESULT FAIL")
		get_tree().quit()
		return
	GameState.boss_phase_changed.connect(func(b: Node, ph: int, final: bool) -> void: _beats.append([b, ph, final]))

	# (3) the arrival: BEHEMOTH-X's wake-slam announces it.
	var sm: Node3D = (load("res://scenes/enemies/smasher.tscn") as PackedScene).instantiate()
	add_child(sm)
	sm.global_position = Vector3(0, 0.1, -20)
	var top: Control = presence.get("_bar_top")
	var name_label: Label = presence.get("_title")
	var epithet_label: Label = presence.get("_epithet")
	# The card runs on real time (the wake-slam's hit-stop must not stall it),
	# so watch frames for its peak rather than sampling at one game time.
	var bar_peak := 0.0
	var title_peak := 0.0
	for i in 240:
		await get_tree().process_frame
		bar_peak = maxf(bar_peak, top.size.y)
		if name_label.visible:
			title_peak = maxf(title_peak, name_label.modulate.a)
		if bar_peak > 20.0 and title_peak > 0.95:
			break
	_check("letterbox bars slide in", bar_peak > 20.0, "(%.0f px)" % bar_peak)
	_check("the card names the boss", title_peak > 0.95 and name_label.text == "BEHEMOTH-X", "(%s, alpha %.2f)" % [name_label.text, title_peak])
	await _wait(0.5)
	_check("the card holds", name_label.visible and name_label.modulate.a > 0.95 and top.size.y > 20.0, "(alpha %.2f, bars %.0f px)" % [name_label.modulate.a, top.size.y])
	_check("the card shows its epithet", epithet_label != null and epithet_label.text == tr(String(sm.get("boss_epithet"))), "(%s)" % (epithet_label.text if epithet_label else "?"))
	await _wait(4.0)
	_check("the card clears", (not name_label.visible or name_label.modulate.a < 0.05) and top.size.y < 1.0, "(alpha %.2f, bars %.0f px)" % [name_label.modulate.a, top.size.y])

	# (4) notches
	var marks: Array = presence.get("_marks")
	_check("boss bar notched at its phase marks", marks == [0.66, 0.33], "(%s)" % [marks])

	# (5) damage trail
	var hp: Node = sm.get_node("Damageable")
	hp.set("invulnerable", false)
	hp.set("armor", 0.0)
	var maxh: float = hp.get("max_health")
	hp.call("apply_damage", maxh * 0.1, null)
	await _wait(0.2)
	var bar: ProgressBar = hud.get("boss_health_bar")
	var chip: float = presence.get("_chip")
	_check("a hit leaves a damage trail", chip > float(bar.value) / float(bar.max_value) + 0.05, "(trail %.2f, bar %.2f)" % [chip, float(bar.value) / float(bar.max_value)])
	await _wait(1.6)
	chip = presence.get("_chip")
	_check("the trail drains to the bar", absf(chip - float(bar.value) / float(bar.max_value)) < 0.01, "(trail %.2f)" % chip)

	# (6) phase beats
	var rings_before := _rings()
	hp.call("apply_damage", maxh * 0.3, null) # 90 % -> 60 %
	await _wait(0.3)
	var banner: Label = presence.get("_banner")
	_check("crossing 66 % stages phase II once", _beats.size() == 1 and _beats[0][1] == 2 and not _beats[0][2], "(%s)" % [_beats])
	_check("phase II banner", banner != null and banner.visible and banner.text == tr("PHASE II"), "(%s)" % (banner.text if banner else "?"))
	_check("phase beat throws a shockwave ring", _rings() > rings_before, "(%d -> %d)" % [rings_before, _rings()])
	await _wait(2.5)
	hp.call("apply_damage", maxh * 0.05, null) # still phase II
	await _wait(0.2)
	_check("no beat without a new phase", _beats.size() == 1, "(%d beats)" % _beats.size())
	hp.call("apply_damage", maxh * 0.25, null) # -> 30 %
	await _wait(0.3)
	_check("crossing 33 % stages the final phase", _beats.size() == 2 and _beats[1][1] == 3 and _beats[1][2], "(%s)" % [_beats])
	_check("final phase banner", banner.visible and banner.text == tr("FINAL PHASE"), "(%s)" % banner.text)
	# (7) a hitch frame (the boss's materials compiling on its first frame)
	# must not skip the card: it advances at most a step.
	Engine.time_scale = 1.0
	presence.call("_on_boss_spawned", sm)
	presence.call("_process", 4.0)
	_check("a 4 s hitch frame does not skip the card", name_label.visible and float(presence.get("_card_t")) <= 0.06, "(card at %.2f s)" % float(presence.get("_card_t")))
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
