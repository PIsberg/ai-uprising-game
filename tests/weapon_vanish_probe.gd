extends Node
## Repro probe for "gun vanishes from view after one shot, can't shoot more".
## Loads level_01, grabs the player (starts with the PISTOL — a SEMI weapon, which
## the convoy bot never used), fires ONE semi shot the way a human clicks
## (press then release), then reports the viewmodel/weapon state and whether a
## second shot can land. Screenshots before + after so a purely-visual vanish
## still shows up.
##   godot --path . res://tests/weapon_vanish_probe.tscn   (windowed, real render)

const SHOT_DIR := "user://vanish_probe"

func _ready() -> void:
	_run.call_deferred()

func _dump(w) -> String:
	var vm = w.viewmodel
	var vm_vis := "n/a"
	var vm_pos := "n/a"
	if vm:
		vm_vis = str(vm.visible)
		vm_pos = str(vm.position)
	return "weapon.visible=%s mag=%d reserve=%d cooldown=%.2f reloading=%s vm.visible=%s vm.pos=%s" % [
		w.visible, w.mag, w.reserve, w.get("_cooldown"), w.get("_reloading"), vm_vis, vm_pos]

func _run() -> void:
	GameState.current_level_path = "res://scenes/levels/level_01.tscn"
	var lvl: Node = load(GameState.current_level_path).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.0).timeout
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player == null:
		print("NO PLAYER"); get_tree().quit(); return
	GameState.set_state(GameState.State.PLAYING)
	var wh = player.get_node_or_null("Head/Camera3D/WeaponHolder")
	if wh == null:
		print("NO WEAPON HOLDER"); get_tree().quit(); return
	var w = wh.current
	print("start: current=%s" % (w.scene_file_path if w else "<null>"))
	print("  before fire: ", _dump(w))
	print("  equip_timer=%.2f" % wh.get("_equip_timer"))

	# Let the draw/equip timer expire so firing is allowed.
	await get_tree().create_timer(1.0).timeout
	print("  after draw wait: equip_timer=%.2f  %s" % [wh.get("_equip_timer"), _dump(w)])

	_screenshot("before")

	# ONE human-style click: press fire for a few frames, then release.
	Input.action_press("fire")
	for i in 5:
		await get_tree().process_frame
	Input.action_release("fire")
	for i in 5:
		await get_tree().process_frame
	print("  after 1 shot: ", _dump(w))
	print("    wh.current now=%s (index=%d)" % [wh.current, wh.get("current_index")])
	_screenshot("after1")

	# Try to fire a SECOND time.
	var mag_before: int = w.mag
	Input.action_press("fire")
	for i in 8:
		await get_tree().process_frame
	Input.action_release("fire")
	for i in 5:
		await get_tree().process_frame
	var w2 = wh.current
	print("  after 2nd click: current=%s  %s" % [w2, _dump(w2) if w2 else "<null>"])
	print("    second shot landed=%s (mag %d -> %d)" % [w2 and w2.mag < mag_before, mag_before, w2.mag if w2 else -1])
	_screenshot("after2")

	# Hold auto-ish: many frames of fire held.
	Input.action_press("fire")
	for i in 40:
		await get_tree().process_frame
	Input.action_release("fire")
	var w3 = wh.current
	print("  after held burst: current=%s  %s" % [w3, _dump(w3) if w3 else "<null>"])
	_screenshot("after_hold")

	# --- ADS + fire (right-click aim held while shooting) ---
	Input.action_press("aim")
	for i in 10:
		await get_tree().process_frame
	Input.action_press("fire")
	for i in 6:
		await get_tree().process_frame
	Input.action_release("fire")
	for i in 4:
		await get_tree().process_frame
	Input.action_release("aim")
	var wa = wh.current
	print("  after ADS shot: current=%s  %s" % [wa, _dump(wa) if wa else "<null>"])
	_screenshot("after_ads")

	# --- alt-fire (V): the charge/volley/slug path the bots never touch ---
	Input.action_press("alt_fire")
	for i in 30:
		await get_tree().process_frame
	Input.action_release("alt_fire")
	for i in 10:
		await get_tree().process_frame
	var wv = wh.current
	print("  after alt-fire: current=%s  %s" % [wv, _dump(wv) if wv else "<null>"])
	_screenshot("after_alt")
	get_tree().quit()

func _screenshot(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var p := "%s/%s.png" % [SHOT_DIR, tag]
	img.save_png(p)
	print("  [shot] %s -> %s" % [tag, ProjectSettings.globalize_path(p)])
