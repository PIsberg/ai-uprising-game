extends Node3D
## Windowed: photographs floor that two crossing route gates used to wall off
## (#500), now open (LevelBuilder.gate_span). Two frames into user://:
## mistral's north-east corner seen from the spawn strip, where the east
## bulkhead used to run on to the north wall (sealed_floor_mistral.png), and
## gemini's east strip seen from the middle band (sealed_floor_gemini.png).
##   godot --path . res://tests/sealed_floor_shot.tscn

const SHOTS := [
	["mistral", Vector3(22, 2.4, -41), Vector3(40, 1.0, -38)],
	["gemini", Vector3(24, 2.4, 0), Vector3(44, 1.0, 0)],
]

func _ready() -> void:
	for s in SHOTS:
		var lvl: Node = (load("res://scenes/levels/level_%s.tscn" % s[0]) as PackedScene).instantiate()
		add_child(lvl)
		await get_tree().create_timer(2.0).timeout
		for h in get_tree().get_nodes_in_group("hud"):
			h.visible = false
		var cam := Camera3D.new()
		add_child(cam)
		cam.global_position = s[1]
		cam.look_at(s[2])
		cam.fov = 80.0
		cam.make_current()
		await get_tree().create_timer(0.6).timeout
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/sealed_floor_%s.png" % s[0])
		cam.queue_free()
		lvl.queue_free()
		await get_tree().create_timer(0.4).timeout
	print("SEALED_FLOOR_SHOT_DONE")
	get_tree().quit()
