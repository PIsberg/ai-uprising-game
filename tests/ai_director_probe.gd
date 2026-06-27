extends Node
## Dev probe: unit-checks the Adaptive AI Director's counter logic — feeds it a few
## synthetic playstyle profiles and asserts it picks the affix meant to counter each.
##   godot --headless --path . res://tests/ai_director_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ok := true
	ok = _case("precise aim", {"acc": 0.62}, "warden") and ok
	ok = _case("headshot hunter", {"head": 0.5}, "warden") and ok
	ok = _case("long-range sniper", {"range": 0.8}, "swift") and ok
	ok = _case("one-weapon spammer", {"focus": 0.85}, "shielded") and ok
	ok = _case("point-blank brawler", {"range": 0.2}, "shielded") and ok
	ok = _case("static camper", {"mob": 0.2}, "shielded") and ok
	# Still calibrating -> no bias.
	AIDirector.reset_profile()
	var calib := AIDirector.counter_affix()
	print("calibrating -> '%s' (expect '')" % calib)
	if calib != "":
		ok = false
	# A strong profile should produce a taunt.
	_set_profile({"acc": 0.7, "range": 0.8})
	var t := AIDirector.taunt()
	print("taunt -> '%s'" % t)
	if t == "":
		ok = false
	# Post-level assessment: a sniper profile -> SWIFT counter readout; calibrating -> "".
	_set_profile({"range": 0.85})
	var a := AIDirector.assessment()
	print("assessment -> '%s'" % a)
	if not a.contains("SWIFT"):
		ok = false
	AIDirector.reset_profile()
	if AIDirector.assessment() != "":
		ok = false
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _set_profile(s: Dictionary) -> void:
	AIDirector.reset_profile()
	AIDirector._shots = 24 # past MIN_SAMPLES so the read is live
	AIDirector.accuracy = float(s.get("acc", 0.0))
	AIDirector.headshot_rate = float(s.get("head", 0.0))
	AIDirector.range_pref = float(s.get("range", 0.5))
	AIDirector.mobility = float(s.get("mob", 0.5))
	if s.has("focus"):
		AIDirector._weapon_shots = {"Test Gun": int(round(24.0 * float(s["focus"])))}

func _case(label: String, s: Dictionary, expect: String) -> bool:
	_set_profile(s)
	var got := AIDirector.counter_affix()
	var pass_ := got == expect
	print("%-22s -> %-9s (expect %-9s) %s" % [label, got, expect, "OK" if pass_ else "BAD"])
	return pass_
