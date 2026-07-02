extends Node3D
## Loads level_01, cycles through every GraphicsSettings.ColorGrade preset and
## screenshots each so the shift is visually verifiable. Windowed:
##   godot --path . tests/color_grade_probe.tscn
## Saves user://grade_<preset>.png for each preset.

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_01.tscn") as PackedScene).instantiate()
	add_child(lvl)
	var pdmg := lvl.find_child("Damageable", true, false)
	if pdmg:
		pdmg.invulnerable = true
	await get_tree().create_timer(2.0).timeout
	for i in GraphicsSettings.ColorGrade.size():
		GraphicsSettings.set_color_grade(i)
		await get_tree().process_frame
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var out := OS.get_user_data_dir() + "/grade_%s.png" % GraphicsSettings.COLOR_GRADE_LABELS[i]
		img.save_png(out)
		print("SAVED ", out)
	print("DONE")
	get_tree().quit()
