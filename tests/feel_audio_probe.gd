extends Node3D
## Verifies the AAA feel/audio batch end-to-end on a real level (titan = lava):
##  1. every new synth stream resolves (silent-no-op regression guard)
##  2. the lava level layers the hazard ambience bed over the room tone
##  3. low-HP heartbeat starts below ~18% HP and stops when healed
##  4. sprint drops the weapon into the lower-ready pose; the trigger raises it
##  5. blast shock: a close explosion muffles the world low-pass and recovers
##  6. the score ducks while a lore VO line is speaking, and recovers after

func _ready() -> void:
	# 1) Stream registration.
	var ids := ["ear_ring", "heartbeat", "hit_tick", "kill_thock", "brass_tink",
		"ui_deny", "ui_back", "victory_sting"]
	var missing: Array[String] = []
	for id in ids:
		if AudioBus.synth(id) == null:
			missing.append(id)
	print("streams_missing=%s" % [missing])

	var lvl: Node = (load("res://scenes/levels/level_titan.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(1.5).timeout
	GameState.current_state = GameState.State.PLAYING
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	var d = player.get_node("Damageable")

	# 2) Hazard ambience layer (titan def has lava beds).
	var bed: AudioStreamPlayer = AudioBus._ambience2
	print("hazard_layer: playing=%s" % (bed != null and bed.playing))

	# 3) Heartbeat: inside spawn grace, drop HP to 12% -> starts; heal -> stops.
	d.current_health = d.max_health * 0.12
	await get_tree().create_timer(0.3).timeout
	var hb: AudioStreamPlayer = player._heartbeat
	var hb_on: bool = hb != null and hb.playing
	d.current_health = d.max_health
	await get_tree().create_timer(0.3).timeout
	var hb2: AudioStreamPlayer = player._heartbeat
	var hb_off: bool = hb2 == null or not hb2.playing
	print("heartbeat: on_at_12pct=%s off_at_full=%s" % [hb_on, hb_off])

	# 4) Sprint lower-ready pose on the real WeaponManager.
	var wms := player.find_children("*", "WeaponManager", true, false)
	var wm: Node3D = wms[0] if not wms.is_empty() else null
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await get_tree().create_timer(1.4).timeout
	var spd := Vector2(player.velocity.x, player.velocity.z).length()
	if spd < 7.0: # spawn faced a wall — run the other way instead
		Input.action_release("move_forward")
		Input.action_press("move_back")
		await get_tree().create_timer(1.4).timeout
		spd = Vector2(player.velocity.x, player.velocity.z).length()
	var lowered: float = wm._sprint_lerp if wm else -1.0
	Input.action_press("fire") # trigger must break the pose fast
	await get_tree().create_timer(0.35).timeout
	var raised: float = wm._sprint_lerp if wm else -1.0
	Input.action_release("fire")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	Input.action_release("move_back")
	print("sprint_pose: speed=%.1f lowered=%.2f raised=%.2f" % [spd, lowered, raised])

	# 5) Blast shock via the play_synth_at("explosion") auto-hook.
	var cam := get_viewport().get_camera_3d()
	AudioBus.play_synth_at("explosion", cam.global_position + Vector3(2, 0, 0), 2.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var shock_peak: float = AudioBus._shock
	var lp = AudioBus._shock_lp
	var lp_cut: float = lp.cutoff_hz if lp else -1.0
	await get_tree().create_timer(3.0).timeout
	var lp_after: float = AudioBus._shock_lp.cutoff_hz if AudioBus._shock_lp else -1.0
	print("blast_shock: peak=%.2f lp_during=%.0fHz lp_after=%.0fHz shock_after=%.2f" % [
		shock_peak, lp_cut, lp_after, AudioBus._shock])

	# 6) VO duck while a lore line speaks.
	AudioBus.play_lore("lore_gpt")
	await get_tree().create_timer(0.8).timeout
	var duck_during: float = AudioBus._vo_duck
	if AudioBus._lore_player:
		AudioBus._lore_player.stop()
	await get_tree().create_timer(1.2).timeout
	print("vo_duck: during=%.2f after=%.2f" % [duck_during, AudioBus._vo_duck])

	print("FEEL_AUDIO_PROBE_DONE")
	get_tree().quit()
