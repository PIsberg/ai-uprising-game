extends Node
## Headless smoke test for the HUD headshot callout (the small gold "HEADSHOT"
## popup that punches in alongside the kill-streak word on a crit hit).
## Run: godot --headless --path . res://tests/headshot_callout_probe.gd
## Spawns the real player + HUD, fires GameState.report_player_hit with crit=true
## (the same path a headshot hitscan takes through Damageable), then asserts the
## HUD's headshot label became visible. Prints PASS/FAIL and quits with code 0/1.

func _ready() -> void:
	var player_ps: PackedScene = load("res://scenes/player/player.tscn")
	var player := player_ps.instantiate()
	player.add_to_group("player")
	add_child(player)
	var hud_ps: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud := hud_ps.instantiate()
	add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	var failures := 0

	if hud._headshot_label == null:
		print("FAIL: no _headshot_label built"); failures += 1
		print("=== %s ===" % ("ALL PASS" if failures == 0 else "%d FAILURE(S)" % failures))
		get_tree().quit(1)
		return

	# Sanity: a non-crit hit must NOT trigger the callout.
	GameState.report_player_hit(10.0, Vector3.ZERO, false, false)
	await get_tree().process_frame
	if hud._headshot_alpha <= 0.0:
		print("PASS: non-crit hit left headshot callout dormant")
	else:
		print("FAIL: non-crit hit triggered the headshot callout"); failures += 1

	# The real signal path a headshot hitscan takes (Damageable.apply_damage ->
	# GameState.report_player_hit -> player_dealt_damage(crit=true) -> HUD).
	GameState.report_player_hit(25.0, Vector3.ZERO, false, true)
	await get_tree().process_frame
	# The label reads "◎ HEADSHOT!" (arcade style); match the word, not the dressing.
	if hud._headshot_alpha > 0.9 and "HEADSHOT" in hud._headshot_label.text:
		print("PASS: crit hit armed the headshot callout (alpha=%.2f, text=%s)" % [hud._headshot_alpha, hud._headshot_label.text])
	else:
		print("FAIL: crit hit did not arm the headshot callout (alpha=%.2f)" % hud._headshot_alpha); failures += 1

	# Let it run a few frames of fade and confirm it decays (proves the process
	# step is wired, not just the trigger).
	for i in 20:
		await get_tree().process_frame
	if hud._headshot_label.modulate.a < 0.9:
		print("PASS: headshot callout faded over time (modulate.a=%.2f)" % hud._headshot_label.modulate.a)
	else:
		print("FAIL: headshot callout did not fade (modulate.a=%.2f)" % hud._headshot_label.modulate.a); failures += 1

	print("=== %s ===" % ("ALL PASS" if failures == 0 else "%d FAILURE(S)" % failures))
	print("RESULT ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
