extends Node3D
## Probe: the HUD teaches alt-fire (#495). Nothing in play said a gun had a
## secondary fire. Through the real player, WeaponManager and HUD:
##   - the M9 the player starts with shows DOUBLE TAP, and its hint is the
##     first toast of the level;
##   - on a gun with no alt mode (the PALM Cannon) the HUD's alt tag is hidden;
##   - on the Pulse Rifle, Breacher, Maelstrom and Plasma Launcher it shows the
##     mode (VOLLEY, SLUG, FAN, CHARGE) and the key the alt-fire is bound to;
##   - back on the PALM Cannon it hides again;
##   - the tag dims while the magazine holds fewer rounds than one use costs,
##     and lights again when it holds enough;
##   - a rebind of "alt_fire" shows in the tag;
##   - and in the hint (#504): the toast names the live key, in German too,
##     and so do the other hints that name a key ([E], [N], [T], [X]); a
##     bracket that is not a key ([0]) is left alone;
##   - on a gamepad: "alt_fire" has a default pad button, and once a pad
##     button is pressed the tag and the hint name it; a key press turns
##     them back;
##   - in German the tag is translated;
##   - the first time a gun with an alt mode is in hand the mode's hint is
##     toasted, after the pickup's own toast has cleared (the toast line holds
##     one message), and once only: five modes, five hints, however often the
##     guns are drawn again.
## Timed on process frames (a toast lasts 2.4 s).
##   godot --headless --path . --audio-driver Dummy res://tests/alt_tag_probe.tscn

const NO_ALT := "res://scenes/weapons/salvage_palm.tscn" ## the PALM Cannon: the one gun with no alt mode (#496)
const NO_ALT_BEFORE := "res://scenes/weapons/pistol.tscn" ## the M9: DOUBLE TAP since #496, none before

const GUNS := [
	["res://scenes/weapons/rifle.tscn", "VOLLEY", 3],
	["res://scenes/weapons/shotgun.tscn", "SLUG", 1],
	["res://scenes/weapons/magnum.tscn", "FAN", 1],
	["res://scenes/weapons/plasma.tscn", "CHARGE", 3],
]

var ok := true
var manual := 0 ## alt-fire hints this probe emitted itself (5b, 5c)
var hud: Node
var wm: WeaponManager
var hints: Array = [] ## every teach_hint text that names the alt-fire
var alpha_at_hint: Array = [] ## how visible the toast line still was the frame before each such hint
var _alpha := 0.0 ## the toast line's alpha as the last frame drew it (0 with no toast up)

func _process(_delta: float) -> void:
	if hud == null:
		return
	var toast: Label = hud.get("toast")
	_alpha = toast.modulate.a if toast and float(hud.get("_toast_time")) > 0.0 else 0.0

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _tag() -> Label:
	return hud.find_child("AltTag", true, false) as Label

func _shown() -> bool:
	var t := _tag()
	return t != null and t.is_visible_in_tree() and t.text != ""

func _text() -> String:
	var t := _tag()
	return t.text if t != null and t.visible else ""

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

## Wait `sec` seconds of process time.
func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().process_frame
		t += get_process_delta_time()

func _draw(path: String) -> Weapon:
	for i in wm.weapons.size():
		if wm.weapons[i].scene_file_path == path:
			wm._equip(i)
			await _frames(3)
			return wm.weapons[i]
	return null

func _run() -> void:
	GameState.reset_run()
	GameState.set_state(GameState.State.PLAYING)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(40, 1, 40)
	fcs.shape = fbox
	fcs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fcs)
	add_child(floor_body)
	var player: Node3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.2, 0)
	await _frames(3)
	wm = player.get_node_or_null("Head/Camera3D/WeaponHolder") as WeaponManager
	GameState.teach_hint.connect(func(text: String) -> void:
		if text.contains("ALT-FIRE"):
			hints.append(text)
			alpha_at_hint.append(_alpha))
	hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await _frames(4)

	# 0. The starting gun.
	_check("the M9 the player starts with shows DOUBLE TAP and the key", wm.current != null and wm.current.scene_file_path == NO_ALT_BEFORE
			and _shown() and _text().contains("DOUBLE TAP") and _text().contains("[V]"), "'%s'" % _text())
	_check("and its hint is the first toast", hints.size() == 1 and (hints[0] as String).contains("DOUBLE TAP"), str(hints.size()))
	await _wait(2.6)

	# 1. No alt mode: no tag.
	if not wm.add_weapon(load(NO_ALT) as PackedScene): # in the starting rack already: draw it
		await _draw(NO_ALT)
	await _frames(3)
	var plain := wm.current
	_check("the PALM Cannon is in hand and has no alt mode", plain != null and plain.scene_file_path == NO_ALT and plain.data.alt_mode == WeaponData.AltMode.NONE)
	_check("on a gun with no alt mode the tag is hidden", not _shown(), "'%s'" % _text())

	# 2. Each mode shows its name and the key.
	for g in GUNS:
		var path: String = g[0]
		var was := hints.size()
		# A pickup: toasts WEAPON ACQUIRED and switches to it (the Maelstrom is in
		# the starting rack, so it is drawn instead).
		var picked := wm.add_weapon(load(path) as PackedScene)
		if not picked:
			await _draw(path)
		await _frames(3)
		var name := path.get_file().trim_suffix(".tscn")
		_check("%s: the tag names %s and the key" % [name, g[1]], _shown() and _text().contains(String(g[1])) and _text().contains("[V]"), "'%s'" % _text())
		if picked:
			_check("%s: the hint does not stamp over the pickup toast" % name, hints.size() == was, "%d hints in the pickup's frames" % (hints.size() - was))
		await _wait(3.2)
		_check("%s: its hint is toasted once the line is free" % name, hints.size() == was + 1 and hints[-1].contains(String(g[1])) and alpha_at_hint[-1] < 0.05,
				"%d new, '%s', the old toast at alpha %.2f" % [hints.size() - was, (hints[-1] as String).left(40) if hints.size() > was else "", alpha_at_hint[-1] if hints.size() > was else -1.0])
		await _wait(2.6)

	# 3. Back on the PALM Cannon it hides.
	await _draw(NO_ALT)
	_check("back on the PALM Cannon the tag hides again", not _shown(), "'%s'" % _text())

	# 4. Dim when one use costs more than the magazine holds.
	var plasma := await _draw("res://scenes/weapons/plasma.tscn")
	var lit := _tag().modulate.a if _tag() else 0.0
	plasma.mag = 2
	plasma.ammo_changed.emit(plasma.mag, plasma.reserve)
	await _frames(2)
	var dim := _tag().modulate.a if _tag() else 0.0
	plasma.mag = 3
	plasma.ammo_changed.emit(plasma.mag, plasma.reserve)
	await _frames(2)
	var relit := _tag().modulate.a if _tag() else 0.0
	_check("the tag dims at 2 rounds on a 3-round CHARGE and lights again at 3", lit > 0.9 and dim < 0.5 and relit > 0.9, "%.2f, %.2f, %.2f" % [lit, dim, relit])
	var shot := await _draw("res://scenes/weapons/shotgun.tscn")
	shot.mag = 1
	shot.ammo_changed.emit(shot.mag, shot.reserve)
	await _frames(2)
	var one := _tag().modulate.a if _tag() else 0.0
	shot.mag = 0
	shot.ammo_changed.emit(shot.mag, shot.reserve)
	await _frames(2)
	var none := _tag().modulate.a if _tag() else 0.0
	_check("a SLUG needs one shell: lit at 1, dim at 0", one > 0.9 and none < 0.5, "%.2f, %.2f" % [one, none])
	shot.mag = 4
	shot.ammo_changed.emit(shot.mag, shot.reserve)

	# 5. A rebind shows.
	var before := InputMap.action_get_events("alt_fire")
	InputMap.action_erase_events("alt_fire")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_B
	InputMap.action_add_event("alt_fire", ev)
	await _draw("res://scenes/weapons/rifle.tscn")
	_check("a rebind of alt_fire shows in the tag", _text().contains("[B]") and not _text().contains("[V]"), "'%s'" % _text())
	# 5b. And in the hint (#504). The hint text is the translation key, so it
	# is emitted with [V] and the HUD fills the live key in after tr().
	var toast := hud.get_node("Toast") as Label
	manual += 1
	GameState.teach_hint.emit(GameState.MECHANIC_HINTS["alt_volley"])
	await _frames(2)
	_check("the hint names the rebound key", toast.text.contains("tap [B]") and not toast.text.contains("[V]"), "'%s'" % toast.text)
	var was_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("de")
	manual += 1
	GameState.teach_hint.emit(GameState.MECHANIC_HINTS["alt_charge"])
	await _frames(2)
	_check("in German too", toast.text.contains("[B]") and not toast.text.contains("[V]") and toast.text != GameState.MECHANIC_HINTS["alt_charge"].replace("[V]", "[B]"), "'%s'" % toast.text)
	TranslationServer.set_locale(was_locale)
	var other := {"interact": ["uplink", KEY_J, "[E]", "[J]"], "night_vision": ["night_vision", KEY_K, "[N]", "[K]"],
			"adversarial_patch": ["patch_key", KEY_L, "[T]", "[L]"], "ultimate": ["overload", KEY_M, "[X]", "[M]"]}
	for action: String in other:
		var o: Array = other[action]
		var had := InputMap.has_action(action)
		var kept: Array = InputMap.action_get_events(action) if had else []
		if not had:
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var oe := InputEventKey.new()
		oe.physical_keycode = o[1]
		InputMap.action_add_event(action, oe)
		GameState.teach_hint.emit(GameState.MECHANIC_HINTS[o[0]])
		await _frames(2)
		_check("the %s hint names its rebound key" % o[0], GameState.MECHANIC_HINTS[o[0]].contains(o[2]) and toast.text.contains(o[3]) and not toast.text.contains(o[2]), "'%s'" % toast.text.left(70))
		InputMap.action_erase_events(action)
		for e in kept:
			InputMap.action_add_event(action, e)
	GameState.teach_hint.emit("a list [0] and a key [V]")
	await _frames(2)
	_check("a bracket that is not a key is left alone", toast.text == "a list [0] and a key [B]", "'%s'" % toast.text)
	InputMap.action_erase_events("alt_fire")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_XBUTTON2
	InputMap.action_add_event("alt_fire", mb)
	await _draw("res://scenes/weapons/magnum.tscn")
	_check("with only a mouse button bound the tag names the button", _text().contains("[MOUSE 9]"), "'%s'" % _text())
	InputMap.action_erase_events("alt_fire")
	for e in before:
		InputMap.action_add_event("alt_fire", e)

	# 5c. A gamepad. The default binding has a pad button, in the live map
	# and in the rebind screen's factory defaults.
	var pad_btn := -1
	for e in before:
		if e is InputEventJoypadButton:
			pad_btn = (e as InputEventJoypadButton).button_index
	var fac_btn := -1
	for e in GraphicsSettings._factory_default_events("alt_fire"):
		if e is InputEventJoypadButton:
			fac_btn = (e as InputEventJoypadButton).button_index
	var taken := ""
	for a in InputMap.get_actions():
		if a != &"alt_fire" and not String(a).begins_with("ui_"):
			for e in InputMap.action_get_events(a):
				if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == pad_btn:
					taken = String(a)
	_check("alt_fire has a default pad button, the same in the rebind screen, shared with no other action", pad_btn >= 0 and fac_btn == pad_btn and taken == "", "live %d, factory %d, also on '%s'" % [pad_btn, fac_btn, taken])
	await _draw("res://scenes/weapons/rifle.tscn")
	_check("on keyboard the tag still names the key", _text().contains("[V]"), "'%s'" % _text())
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(3)
	_check("after a pad button the tag names the pad button", _shown() and not _text().contains("[V]") and _text().contains("[BACK]"), "'%s'" % _text())
	manual += 1
	GameState.teach_hint.emit(GameState.MECHANIC_HINTS["alt_volley"])
	await _frames(2)
	_check("and so does the hint", toast.text.contains("tap [BACK]"), "'%s'" % toast.text.left(60))
	var keypress := InputEventKey.new()
	keypress.physical_keycode = KEY_W
	keypress.pressed = true
	Input.parse_input_event(keypress)
	await _frames(3)
	_check("a key press turns the tag back", _text().contains("[V]"), "'%s'" % _text())
	keypress = keypress.duplicate()
	keypress.pressed = false
	Input.parse_input_event(keypress)
	await _frames(2)
	await _draw("res://scenes/weapons/magnum.tscn")

	# 6. Translated.
	var locale := TranslationServer.get_locale()
	TranslationServer.set_locale("de")
	await _draw("res://scenes/weapons/rifle.tscn")
	_check("in German the tag is translated", _text().contains("SALVE") and _text().contains("[V]"), "'%s'" % _text())
	TranslationServer.set_locale(locale)

	# 7. Once only.
	for g in GUNS:
		await _draw(NO_ALT)
		await _draw(String(g[0]))
		await _wait(0.4)
	await _draw(NO_ALT_BEFORE)
	await _wait(3.0)
	_check("five modes, five hints, however often the guns are drawn", hints.size() - manual == 5, "%d, %d of them emitted by this probe" % [hints.size(), manual])

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
