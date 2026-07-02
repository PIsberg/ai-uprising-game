extends Node
## Throwaway visual check: loads the Uplink level with its HUD, screenshots the
## objective checklist through the mission arc (staged ◇ -> live ▢ -> done ✔).
##   godot --path . tools/objective_hud_capture.tscn

const OUT := "res://docs/screenshots/objectives"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_run.call_deferred()

func _run() -> void:
	var lvl: Node = load("res://scenes/levels/level_uplink.tscn").instantiate()
	add_child(lvl)
	await get_tree().create_timer(1.5).timeout
	_snap("arc_0_staged")
	GameState.complete_task("uplink")
	await get_tree().create_timer(1.0).timeout
	_snap("arc_1_key_live")
	GameState.complete_task("key")
	await get_tree().create_timer(1.0).timeout
	_snap("arc_2_boost_live")
	print("OBJECTIVE HUD CAPTURED")
	get_tree().quit()

func _snap(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, name])
