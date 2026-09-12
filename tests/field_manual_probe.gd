extends Node3D
## Verifies the in-run FIELD MANUAL overlay reached from the pause menu (backlog:
## "In-run quick reference"). Loads a real level (enemies + weapon rack), pauses,
## opens the overlay via hud.gd's open_field_manual()/close_field_manual(), and
## checks: the pause panel hides while the overlay shows (still PAUSED); live
## enemies are grouped by codex key with discovered ones showing name/weak/counter
## text and undiscovered ones redacted to "UNIDENTIFIED SIGNATURE"; the arsenal
## lists one row per weapon in the rack with the equipped one marked "> "; Back
## returns to the pause panel without unpausing; Resume closes the overlay too.

var _fail: Array[String] = []

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail.append(label)

## Recursively find the node whose attached script is scripts/ui/hud.gd.
func _find_hud(n: Node) -> Node:
	var s: Script = n.get_script()
	if s and String(s.resource_path).ends_with("hud.gd"):
		return n
	for c in n.get_children():
		var found := _find_hud(c)
		if found:
			return found
	return null

## True if any Label under `container` has text matching `pred`.
func _any_label(container: Node, pred: Callable) -> bool:
	for c in container.get_children():
		if c is Label and pred.call((c as Label).text):
			return true
	return false

func _count_labels(container: Node, pred: Callable) -> int:
	var n := 0
	for c in container.get_children():
		if c is Label and pred.call((c as Label).text):
			n += 1
	return n

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	# Short timer steps (not one long await) -- see tests/README probe rules.
	for i in 9:
		await get_tree().create_timer(0.25).timeout
	GameState.current_state = GameState.State.PLAYING
	GameState.current_level_path = "res://scenes/levels/level_gpt.tscn"

	var hud := _find_hud(lvl)
	_check(hud != null, "found the HUD (script hud.gd) under the level")
	if hud == null:
		print("RESULT FAIL")
		get_tree().quit()
		return

	# Live enemies grouped by codex key -- the opening (non-triggered) roster of
	# level_gpt is android x1, drone x2, spider x1: 3 distinct types.
	var counts: Dictionary = {}
	for n in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(n) or not n.has_method("codex_key"):
			continue
		counts[n.codex_key()] = int(counts.get(n.codex_key(), 0)) + 1
	print("live codex keys: %s" % [counts])
	_check(counts.size() >= 2, "at least 2 distinct live enemy types spawned (%d)" % counts.size())

	# Back up the bestiary save (discover_enemy persists it), restore at the end.
	var bestiary_path := "user://bestiary.cfg"
	var backup: PackedByteArray = PackedByteArray()
	var had_backup := false
	if FileAccess.file_exists(bestiary_path):
		var rf := FileAccess.open(bestiary_path, FileAccess.READ)
		backup = rf.get_buffer(rf.get_length())
		rf.close()
		had_backup = true

	# Force a clean discovery slate for this probe -- the real user's bestiary
	# save may already have some of these types discovered from actual play,
	# which would make the "still redacted" assertion below flaky.
	GameState.discovered_enemies.clear()
	var keys: Array = counts.keys()
	var discovered_keys: Array = []
	var undiscovered_keys: Array = []
	for i in keys.size():
		if i < 2:
			GameState.discover_enemy(keys[i])
			discovered_keys.append(keys[i])
		else:
			undiscovered_keys.append(keys[i])
	print("discovered: %s  undiscovered: %s" % [discovered_keys, undiscovered_keys])

	# ---- pause + open the manual -------------------------------------------
	GameState.set_state(GameState.State.PAUSED)
	hud._enter_pause()
	hud.open_field_manual()
	await get_tree().process_frame

	_check(hud.field_manual_overlay.visible, "overlay visible after open_field_manual")
	_check(not hud.pause_menu.visible, "pause panel hidden while overlay is open")
	_check(GameState.current_state == GameState.State.PAUSED, "still PAUSED with the overlay open")

	# One threat row per distinct live type: a name+count line ("... xN") for
	# discovered types, or "UNIDENTIFIED SIGNATURE  xN" for undiscovered ones.
	var re := RegEx.new()
	re.compile("x\\d+$")
	var threat_rows := _count_labels(hud._fm_content, func(t: String): return re.search(t) != null)
	_check(threat_rows == counts.size(), "threat rows (%d) == distinct live codex keys (%d)" % [threat_rows, counts.size()])

	for k in discovered_keys:
		var entry := EnemyCodex.get_entry(k)
		var nm := String(entry.get("name", k.to_upper()))
		_check(_any_label(hud._fm_content, func(t: String): return t.begins_with(nm)),
			"discovered type %s shows its codex name" % k)
	for k in undiscovered_keys:
		_check(_any_label(hud._fm_content, func(t: String): return t.begins_with("UNIDENTIFIED SIGNATURE")),
			"undiscovered type %s is redacted to UNIDENTIFIED SIGNATURE" % k)

	# Arsenal: one "... dmg ..." stat row per weapon in the rack, equipped one
	# marked with the leading "> ".
	var arsenal_rows := _count_labels(hud._fm_content, func(t: String): return t.contains(" dmg "))
	_check(hud._wm != null, "HUD has a WeaponManager reference")
	if hud._wm:
		_check(arsenal_rows == hud._wm.weapons.size(), "arsenal rows (%d) == rack size (%d)" % [arsenal_rows, hud._wm.weapons.size()])
		var equipped_rows := _count_labels(hud._fm_content, func(t: String): return t.begins_with("> "))
		_check(equipped_rows == 1, "exactly one weapon row is marked equipped (%d)" % equipped_rows)

	# ---- close: back to the pause panel, still paused ----------------------
	hud.close_field_manual()
	await get_tree().process_frame
	_check(not hud.field_manual_overlay.visible, "overlay hidden after close_field_manual")
	_check(hud.pause_menu.visible, "pause panel visible again after closing the overlay")
	_check(GameState.current_state == GameState.State.PAUSED, "still PAUSED after closing the overlay")

	# ---- resume: overlay stays hidden, back to PLAYING ----------------------
	hud.open_field_manual() # reopen so resume's defensive close is actually exercised
	await get_tree().process_frame
	hud._on_resume_pressed()
	await get_tree().process_frame
	_check(not hud.field_manual_overlay.visible, "overlay hidden after resuming")
	_check(GameState.current_state == GameState.State.PLAYING, "back to PLAYING after resume")

	# Restore the bestiary save so this probe leaves no trace on the real save.
	if had_backup:
		var wf := FileAccess.open(bestiary_path, FileAccess.WRITE)
		wf.store_buffer(backup)
		wf.close()
	else:
		var da := DirAccess.open("user://")
		if da:
			da.remove("bestiary.cfg")

	print("RESULT %s" % ("PASS" if _fail.is_empty() else "FAIL"))
	if not _fail.is_empty():
		print("failed: %s" % ", ".join(_fail))
	get_tree().quit()