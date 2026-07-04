extends Node
## Headless smoke test for the key-rebind persistence layer (GraphicsSettings).
## Run: godot --headless --path . res://tests/keybind_probe.gd
##
## Exercises: factory defaults are correct at boot, rebind_action() applies to
## the live InputMap, the swap/steal conflict policy fires, a saved override
## survives a simulated reload (_load_settings + apply_keybinds), and
## reset_keybinds_to_default() restores the factory baseline. Prints PASS/FAIL
## lines and quits with code 0 on success.

func _ready() -> void:
	var failures := 0

	# --- 1) Factory defaults are live at boot (main-menu time, no level ever loaded) ---
	if _has_key_event("dash", KEY_Q):
		print("PASS: dash defaults to Q")
	else:
		print("FAIL: dash missing default Q binding"); failures += 1

	if _has_key_event("melee", KEY_F) and InputMap.has_action("melee"):
		print("PASS: melee (runtime-only action) pre-registered with default F, no level ever loaded")
	else:
		print("FAIL: melee not proactively registered with its default bind"); failures += 1

	if _has_key_event("weapon_1", KEY_1):
		print("PASS: weapon_1 defaults to 1")
	else:
		print("FAIL: weapon_1 missing default"); failures += 1

	# --- 2) Rebind dash's kb slot to T ---
	GraphicsSettings.rebind_action("dash", false, _mk_key(KEY_T))
	if _has_key_event("dash", KEY_T) and not _has_key_event("dash", KEY_Q):
		print("PASS: dash rebound Q -> T")
	else:
		print("FAIL: dash rebind to T did not apply"); failures += 1

	# --- 3) Conflict policy: rebinding melee to T must steal it from dash (swap) ---
	var stolen := GraphicsSettings.rebind_action("melee", false, _mk_key(KEY_T))
	if _has_key_event("melee", KEY_T) and not _has_key_event("dash", KEY_T):
		print("PASS: melee rebind to T stole the key away from dash")
	else:
		print("FAIL: conflict swap did not move T from dash to melee"); failures += 1
	if stolen.has("Dash"):
		print("PASS: rebind_action reported the steal (%s)" % str(stolen))
	else:
		print("FAIL: rebind_action did not report stealing from Dash (got %s)" % str(stolen)); failures += 1

	# --- 4) Gamepad slot independent of kb slot: rebind grapple's gamepad button ---
	GraphicsSettings.rebind_action("grapple", true, _mk_joy(JOY_BUTTON_Y))
	if _has_joy_event("grapple", JOY_BUTTON_Y) and _has_key_event("grapple", KEY_C):
		print("PASS: grapple gamepad slot rebound to Y, kb slot (C) untouched")
	else:
		print("FAIL: grapple gamepad rebind clobbered the kb slot or didn't apply"); failures += 1

	# --- 5) Persistence roundtrip: simulate a fresh GraphicsSettings load ---
	InputMap.action_erase_events("dash")
	InputMap.action_add_event("dash", _mk_key(KEY_Q)) # scramble the live InputMap
	GraphicsSettings.keybind_overrides.clear() # scramble in-memory state too
	GraphicsSettings._load_settings() # re-reads user://settings.cfg
	GraphicsSettings.apply_keybinds() # re-applies onto InputMap
	# dash's kb slot was stolen away by melee in step 3 (swap policy — it isn't
	# replaced with anything), so the correct post-reload state is: dash has NO
	# kb event and keeps its untouched gamepad R3 default; melee kept T.
	if not _has_key_event("dash", KEY_Q) and not _has_key_event("dash", KEY_T) \
			and _has_joy_event("dash", JOY_BUTTON_RIGHT_STICK) and _has_key_event("melee", KEY_T):
		print("PASS: saved override (incl. the steal) survived a simulated GraphicsSettings reload")
	else:
		print("FAIL: override lost across reload (dash=%s, melee=%s)" % [_event_keys("dash"), _event_keys("melee")])
		failures += 1

	# --- 6) Reset to defaults restores the factory baseline ---
	GraphicsSettings.reset_keybinds_to_default()
	if _has_key_event("dash", KEY_Q) and _has_key_event("melee", KEY_F) \
			and _has_joy_event("grapple", JOY_BUTTON_LEFT_SHOULDER):
		print("PASS: reset_keybinds_to_default restored dash=Q, melee=F, grapple pad=LB")
	else:
		print("FAIL: reset did not restore factory defaults"); failures += 1

	print("=== %s ===" % ("ALL PASS" if failures == 0 else "%d FAILURE(S)" % failures))
	get_tree().quit(0 if failures == 0 else 1)

func _mk_key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

func _mk_joy(btn: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	return e

func _has_key_event(action: String, code: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == code:
			return true
	return false

func _has_joy_event(action: String, btn: int) -> bool:
	if not InputMap.has_action(action):
		return false
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == btn:
			return true
	return false

func _event_keys(action: String) -> Array:
	var out: Array = []
	for e in InputMap.action_get_events(action):
		out.append(e)
	return out
