extends Node3D
## Verifies PROMETHEUS-0's phase-blink no longer fires an instant, undodgeable
## on-target beam. After a blink the beam must CHARGE (BLINK_BEAM_TELL) before it
## sweeps — giving the player a reaction window at the new angle.
## Expect: right after blink -> beam NOT yet firing (_beam_time==0) but a delay is
## armed (_blink_beam_delay>0); after the tell elapses -> beam fires (_beam_time>0).
## Run: godot --headless --path . res://tests/titan_blink_probe.tscn

func _ready() -> void:
	var nav := NavigationRegion3D.new(); add_child(nav)
	# A player target well outside preferred_range so the blink is "worth it".
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pcs := CollisionShape3D.new(); var cap := CapsuleShape3D.new()
	cap.radius = 0.4; cap.height = 1.7; pcs.shape = cap; player.add_child(pcs)
	var pdmg := Damageable.new(); pdmg.name = "Damageable"; pdmg.max_health = 9999.0
	pdmg.invulnerable = true; player.add_child(pdmg)
	add_child(player)
	player.global_position = Vector3(0, 1, 0)

	var titan: EnemyTitan = (load("res://scenes/enemies/titan.tscn") as PackedScene).instantiate()
	add_child(titan)
	titan.global_position = Vector3(0, 0.5, 60)  # far away → dist > preferred_range
	await get_tree().process_frame
	await get_tree().process_frame

	# Force target + phase 2 (health <= 66%) and clear the blink cooldown.
	titan.target = player
	titan.hp.current_health = titan.hp.max_health * 0.5
	titan._blink_cd = 0.0

	var dist: float = titan.global_position.distance_to(player.global_position)
	var blinked: bool = titan._try_blink(dist)

	var beam_at_blink: float = titan._beam_time
	var delay_armed: float = titan._blink_beam_delay
	print("BLINK blinked=%s  beam_time_immediately=%.2f  blink_beam_delay=%.2f" % [
		blinked, beam_at_blink, delay_armed])

	# Advance ~0.7s of processing so the tell elapses and the beam should ignite.
	var t := 0.0
	var fired := false
	var fire_at := -1.0
	while t < 0.9:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		# Drive the boss brain so _blink_beam_delay counts down (titan._process).
		if titan._beam_time > 0.0 and not fired:
			fired = true
			fire_at = t
	print("BEAM fired_after_tell=%s  fire_at=%.2fs (tell=%.2f)" % [fired, fire_at, titan.BLINK_BEAM_TELL])

	var ok := blinked and is_zero_approx(beam_at_blink) and delay_armed > 0.0 and fired
	print("TITAN_BLINK ", "OK" if ok else "FAIL")
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
