extends Node3D
## Verifies the PERFECT DODGE reward: a hit negated by the dash i-frame window
## scores a bonus + banner exactly once per dash, and a hit while NOT dashing
## does not (it just wounds you as normal).

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(1.5).timeout
	GameState.current_state = GameState.State.PLAYING
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var d = player.get_node("Damageable")

	# --- Not dashing: a hit should NOT score a dodge ---
	GameState.score = 0
	d.apply_damage(10.0, self)
	await get_tree().process_frame
	print("no-dash hit: score=%d (expect 0 dodge bonus)" % GameState.score)

	# --- Dashing: the i-frames negate the hit -> PERFECT DODGE, once ---
	GameState.score = 0
	player.set("_dash_time", 0.2)
	player.set("_dodge_scored", false)
	d.invulnerable = true               # what the dash sets during its window
	d.apply_damage(10.0, self)          # blocked -> notify_shield_hit -> reward
	d.apply_damage(10.0, self)          # same dash -> must NOT double-score
	await get_tree().process_frame
	print("dash dodge: score=%d (expect %d, one reward only)" % [
		GameState.score, GameState.PERFECT_DODGE_SCORE])

	# Screenshot the PERFECT DODGE banner.
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/dodge.png")

	# --- Cooldown refund: a dodge shaves the adrenaline lockout ---
	GameState._adrenaline_cd = 10.0
	player.set("_dash_time", 0.2)        # re-arm (the earlier dash window has lapsed)
	player.set("_dodge_scored", false)
	d.invulnerable = true                # the lapsed dash cleared it
	d.apply_damage(10.0, self)
	await get_tree().process_frame
	print("adren cd after dodge: %.1f (expect ~%.1f)" % [
		GameState._adrenaline_cd, 10.0 - GameState.PERFECT_DODGE_ADREN_REFUND])
	print("DODGE_PROBE_DONE")
	get_tree().quit()
