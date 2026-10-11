extends Node
## Probe: night vision is found, kept for the run, and toggled.
## (1) a fresh run has none: the toggle does nothing;
## (2) the goggles pickup grants it (and a hint), and is gone;
## (3) "night_vision" is an input action on N (rebindable);
## (4) toggled on, the goggle pass shows over the view; toggled off, it hides;
## (5) unlike the flashlight it does not give the player away in the dark;
## (6) it survives a save and Continue, and a new run takes it away;
## (7) once owned, another goggles pickup removes itself;
## (8) GPT (the first interior) and SUBLEVEL (fought in a blackout) place one.
##   godot --headless --path . --audio-driver Dummy res://tests/night_vision_probe.tscn

const PICKUP := "res://scenes/pickups/night_vision.tscn"
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _wait(sec: float) -> void:
	var n := int(ceil(sec / 0.25))
	for i in n:
		await get_tree().create_timer(0.25).timeout

func _ready() -> void:
	_run.call_deferred()

func _owned() -> bool:
	return GameState.get("has_night_vision") == true

func _nv_on(p: Node) -> bool:
	return p.has_method("night_vision_on") and p.call("night_vision_on")

func _overlay(p: Node) -> CanvasItem:
	return p.find_child("NightVision", true, false) as CanvasItem

func _run() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 1, 40)
	cs.shape = bs
	cs.position.y = -0.5
	floor_body.add_child(cs)
	add_child(floor_body)
	GameState.reset_run()
	var p: Node3D = load("res://scenes/player/player.tscn").instantiate()
	add_child(p)
	p.global_position = Vector3(0, 0.2, 0)
	await _wait(0.5)

	# 1. None yet.
	_check("a fresh run has no night vision", not _owned())
	if p.has_method("toggle_night_vision"):
		p.call("toggle_night_vision")
	_check("without the goggles the toggle does nothing", not _nv_on(p))

	# 2. The pickup.
	if not ResourceLoader.exists(PICKUP):
		_check("the goggles pickup exists", false)
	else:
		var pk: Node3D = (load(PICKUP) as PackedScene).instantiate()
		add_child(pk)
		pk.global_position = Vector3(5, 0, 0)
		await _wait(0.25)
		pk.call("_on_body_entered", p)
		await _wait(0.25)
		_check("the goggles pickup grants night vision", _owned())
		_check("the pickup is gone once taken", not is_instance_valid(pk) or pk.is_queued_for_deletion())

	# 3. Input.
	var on_n := false
	if InputMap.has_action("night_vision"):
		for e in InputMap.action_get_events("night_vision"):
			if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_N:
				on_n = true
	_check("night_vision is an action on N", on_n)
	var listed := false
	for entry in GraphicsSettings.KEYBIND_ACTIONS:
		if entry["action"] == "night_vision":
			listed = true
	_check("night vision is on the rebind screen", listed)

	# 4. Toggle.
	if p.has_method("toggle_night_vision"):
		p.call("toggle_night_vision")
	await _wait(0.5)
	var ov := _overlay(p)
	_check("toggled on: the goggle pass shows", _nv_on(p) and ov != null and ov.visible)

	# 5. Not a give-away.
	_check("night vision does not count as a flashlight", not p.call("flashlight_on"))

	if p.has_method("toggle_night_vision"):
		p.call("toggle_night_vision")
	await _wait(0.5)
	ov = _overlay(p)
	_check("toggled off: the goggle pass hides", not _nv_on(p) and (ov == null or not ov.visible))

	# 6. Save, Continue, new run.
	GameState.save_progress()
	GameState.set("has_night_vision", false)
	GameState.load_progress()
	_check("Continue keeps the goggles", _owned())
	GameState.reset_run()
	_check("a new run starts without them", not _owned())

	# 7. Already owned: a second pickup removes itself.
	GameState.set("has_night_vision", true)
	if ResourceLoader.exists(PICKUP):
		var pk2: Node3D = (load(PICKUP) as PackedScene).instantiate()
		add_child(pk2)
		await _wait(0.25)
		_check("once owned, another goggles pickup removes itself", not is_instance_valid(pk2) or pk2.is_queued_for_deletion())
	GameState.reset_run()

	# 8. Placement.
	for id in ["gpt", "sublevel"]:
		var found := false
		for pick in LevelDefs.get_def(id).get("pickups", []):
			if str(pick.get("type", pick.get("kind", ""))) == "nightvision":
				found = true
		_check("%s places night-vision goggles" % id.to_upper(), found)

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
