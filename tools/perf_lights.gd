extends Node
## Peak concurrent dynamic Light3D during sustained fire + the player/enemy
## weapon-FX light budget (FXLights). Headless: nodes/tweens still run.
func _ready(): _go.call_deferred()
func _lights() -> int:
	var s = get_tree().current_scene
	return s.find_children("*", "Light3D", true, false).size() if s else -1
func _go():
	GameState.current_level_path = "res://scenes/levels/level_gpt.tscn"
	GameState.equipped_weapon = "res://scenes/weapons/rifle.tscn"
	var lvl = load(GameState.current_level_path).instantiate()
	get_tree().root.add_child(lvl); get_tree().current_scene = lvl
	await get_tree().create_timer(2.0).timeout
	GameState.set_state(GameState.State.PLAYING)
	var pl = get_tree().get_first_node_in_group("player") as Node3D
	if pl == null: print("NO PLAYER"); get_tree().quit(); return
	var base := _lights()
	for i in 8:
		var e = load("res://scenes/enemies/gunner.tscn").instantiate()
		lvl.add_child(e); e.global_position = pl.global_position + Vector3(-6 + i*1.5, 0.5, -8)
	pl.rotation.y = 0.0
	var head = pl.get_node_or_null("Head")
	if head: head.rotation.x = 0.0
	await get_tree().create_timer(1.0).timeout
	var peak := 0
	var fxpeak := 0
	Input.action_press("fire")
	for f in 180:
		await get_tree().process_frame
		peak = maxi(peak, _lights()); fxpeak = maxi(fxpeak, FXLights._live)
	Input.action_release("fire")
	print("base_lights=%d  PEAK total Light3D=%d  PEAK weapon-FX lights=%d/budget %d" % [base, peak, fxpeak, FXLights._budget()])
	print("PERF_LIGHTS_DONE"); get_tree().quit()
