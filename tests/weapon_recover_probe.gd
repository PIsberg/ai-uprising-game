extends Node3D
## Injects each way the equipped weapon can "vanish" and asserts the WeaponManager
## watchdog notices AND re-arms the player. This does not explain the reported
## bug — it makes the bug survivable and loud.
##   godot --headless --path . res://tests/weapon_recover_probe.tscn

var _wm: Node
var _ok := true

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["ok  " if cond else "BAD ", name, detail])
	if not cond:
		_ok = false

func _ready() -> void:
	_run.call_deferred()

func _settle(n: int = 4) -> void:
	for i in n:
		await get_tree().physics_frame

func _run() -> void:
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	for i in 60:
		await get_tree().physics_frame
	GameState.set_state(GameState.State.PLAYING)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	_wm = player.get_node_or_null("Head/Camera3D/WeaponHolder")
	await _settle()
	_check("starts armed", _wm.current != null)

	# 1. The weapon node itself is hidden.
	_wm.current.visible = false
	await _settle(6)
	_check("recovers from weapon hidden", _wm.current != null and _wm.current.is_visible_in_tree())

	# 2. An ANCESTOR is hidden — the case the old watchdog could not see at all.
	_wm.visible = false
	await _settle(6)
	_check("recovers from holder hidden", _wm.current != null and _wm.current.is_visible_in_tree())

	# 3. current_index drifts off the end of the rack.
	_wm.current_index = 99
	await _settle(6)
	_check("recovers from bad index", _wm.current != null and _wm.current.is_visible_in_tree(),
		"index=%d" % _wm.current_index)

	# 4. The equipped Weapon node is freed out from under the manager.
	var victim = _wm.current
	victim.queue_free()
	await _settle(8)
	_check("recovers from freed weapon", _wm.current != null and is_instance_valid(_wm.current))
	_check("prunes the dead rack slot", _wm.weapons.size() == 2, "rack=%d" % _wm.weapons.size())
	var all_live := true
	for w in _wm.weapons:
		if w == null or not is_instance_valid(w):
			all_live = false
	_check("no dead slots left in the rack", all_live)

	# 5. It must NOT fight a deliberate hide outside PLAYING (cutscene/death).
	GameState.set_state(GameState.State.MENU)
	_wm.visible = false
	await _settle(6)
	_check("leaves the viewmodel hidden when not playing", not _wm.visible)
	GameState.set_state(GameState.State.PLAYING)
	await _settle(6)
	_check("re-arms once play resumes", _wm.current != null and _wm.current.is_visible_in_tree())

	print("RESULT ", "PASS" if _ok else "FAIL")
	get_tree().quit()
