extends Node3D
## Verifies the blast screen-warp + glitch post pass:
##   * add_screen_shock registers rings, caps at MAX_SCREEN_SHOCKS, and evicts the
##     WEAKEST live ring (not the newest) when a fourth blast lands.
##   * Rings age out after SCREEN_SHOCK_DUR and push one final all-zero array.
##   * A blast in front of the camera packs a sane screen-UV centre, progress in
##     0..1 and its strength; a blast BEHIND the camera leaves its slot zeroed
##     but still expires on schedule.
##   * pulse_glitch decays back to zero on its own clock.
##   * shaders/post_process.gdshader still parses and exposes the new uniforms.
##
## Logic-only, so it runs headless: set_shader_parameter and unproject_position
## both work without a GPU. Actual refraction is judged in a windowed shot.

var _fail: Array[String] = []

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail.append(label)

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(1.5).timeout
	GameState.current_state = GameState.State.PLAYING

	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("add_screen_shock"):
		print("  FAIL player missing add_screen_shock")
		print("RESULT FAIL")
		get_tree().quit()
		return

	# The pass is gated on Advanced Post-Process; force it on so the probe tests
	# the real path rather than the early-out.
	GraphicsSettings.set_advanced_post_process_enabled(true)

	var cam: Camera3D = player.camera
	var fwd := -cam.global_transform.basis.z
	var in_front: Vector3 = cam.global_position + fwd * 8.0
	var behind: Vector3 = cam.global_position - fwd * 8.0

	# --- registration + cap ------------------------------------------------
	player._screen_shocks.clear()
	player.add_screen_shock(in_front, 0.9)
	player.add_screen_shock(in_front, 0.8)
	player.add_screen_shock(in_front, 0.2)   # the weakest — should be evicted
	_check(player._screen_shocks.size() == 3, "three blasts register")

	player.add_screen_shock(in_front, 0.7)
	_check(player._screen_shocks.size() == player.MAX_SCREEN_SHOCKS,
		"a fourth blast does not exceed MAX_SCREEN_SHOCKS")
	var strengths: Array = []
	for e in player._screen_shocks:
		strengths.append(float(e["strength"]))
	_check(not strengths.has(0.2), "the WEAKEST live ring was evicted, not the newest")
	_check(strengths.has(0.7), "the newest blast survived the eviction")

	# --- packing: in front of camera ---------------------------------------
	player._screen_shocks.clear()
	player.add_screen_shock(in_front, 1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var packed: PackedVector4Array = player._shock_packed
	var slot: Vector4 = packed[0]
	_check(slot.w > 0.0, "front blast packs its strength")
	_check(slot.z > 0.0 and slot.z <= 1.0, "progress advances inside 0..1 (got %.3f)" % slot.z)
	_check(slot.x > -0.5 and slot.x < 1.5 and slot.y > -0.5 and slot.y < 1.5,
		"screen-UV centre is on/near screen (got %.2f, %.2f)" % [slot.x, slot.y])

	# --- packing: behind camera --------------------------------------------
	player._screen_shocks.clear()
	player.add_screen_shock(behind, 1.0)
	await get_tree().physics_frame
	_check(player._shock_packed[0].w == 0.0, "blast behind the camera leaves its slot zeroed")
	_check(player._screen_shocks.size() == 1, "...but is still tracked so it expires")

	# --- expiry + the single clean push ------------------------------------
	player._screen_shocks.clear()
	player.add_screen_shock(in_front, 1.0)
	await get_tree().create_timer(player.SCREEN_SHOCK_DUR + 0.25).timeout
	_check(player._screen_shocks.is_empty(), "rings expire after SCREEN_SHOCK_DUR")
	_check(bool(player._shock_clean), "an all-zero array is pushed once on the way down")
	var all_zero := true
	for k in player.MAX_SCREEN_SHOCKS:
		if player._shock_packed[k].w != 0.0:
			all_zero = false
	_check(all_zero, "packed array is fully cleared when idle")

	# --- glitch decay -------------------------------------------------------
	player.pulse_glitch(1.0, 4.0)
	_check(float(player._glitch) > 0.9, "pulse_glitch raises the corruption level")
	await get_tree().create_timer(0.5).timeout
	var mid := float(player._glitch)
	_check(mid < 1.0, "glitch decays (mid=%.2f)" % mid)
	await get_tree().create_timer(0.6).timeout
	_check(float(player._glitch) == 0.0, "glitch settles back to a clean signal")

	# --- shader still parses and carries the new uniforms -------------------
	var sh: Shader = load("res://shaders/post_process.gdshader")
	_check(sh != null, "post_process.gdshader loads")
	if sh:
		var code := sh.code
		_check(code.contains("uniform vec4 shockwaves[3]"), "shader declares the shockwaves array")
		_check(code.contains("uniform float glitch"), "shader declares the glitch uniform")

	print("RESULT %s" % ("PASS" if _fail.is_empty() else "FAIL"))
	if not _fail.is_empty():
		print("failed: %s" % ", ".join(_fail))
	get_tree().quit()
