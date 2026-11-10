extends Node3D
## Windowed: photographs the HUD's alt-fire tag (#495) in a real level. Three
## frames into user://: the Pulse Rifle with its first-time hint up
## (alt_tag_hint.png), the Plasma Launcher's tag lit (alt_tag_lit.png), and the
## same gun at 2 rounds, one short of a CHARGE, tag dim (alt_tag_dim.png).
##   godot --path . res://tests/alt_tag_shot.tscn

func _ready() -> void:
	GameState.reset_run()
	var lvl: Node = (load("res://scenes/levels/level_hivemind.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.5).timeout
	GameState.set_state(GameState.State.PLAYING)
	var player := get_tree().get_first_node_in_group("player")
	var wm := player.get_node("Head/Camera3D/WeaponHolder") as WeaponManager
	wm.add_weapon(load("res://scenes/weapons/rifle.tscn") as PackedScene)
	await get_tree().create_timer(3.4).timeout # the pickup toast clears, the hint goes up
	await _snap("alt_tag_hint")
	wm.add_weapon(load("res://scenes/weapons/plasma.tscn") as PackedScene)
	await get_tree().create_timer(1.0).timeout
	await _snap("alt_tag_lit")
	wm.current.mag = 2
	wm.current.ammo_changed.emit(wm.current.mag, wm.current.reserve)
	await get_tree().create_timer(0.3).timeout
	await _snap("alt_tag_dim")
	print("ALT_TAG_SHOT_DONE")
	get_tree().quit()

func _snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/%s.png" % name)
