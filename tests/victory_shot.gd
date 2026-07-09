extends Node
## Windowed capture of the victory cutscene at fixed timeline moments, so the
## finale can be judged as pixels. Headless renders black.
##   godot --path . res://tests/victory_shot.tscn
const OUT := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/bec5c1e5-b2af-4e88-b1dd-ce92408127e0/scratchpad/victory7"
const AT := [1.5, 4.0, 6.5, 9.0, 12.0, 15.0, 17.5, 19.0]

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var cs: Node = (load("res://scenes/cutscene/victory_cutscene.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(cs)
	await get_tree().process_frame
	var t := 0.0
	var i := 0
	while i < AT.size():
		await get_tree().process_frame
		t += get_process_delta_time()
		if t >= AT[i]:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/t%04.1f.png" % [OUT, AT[i]])
			print("SAVED t=", AT[i])
			i += 1
		if not is_instance_valid(cs):
			break
	print("VICTORY_SHOT_DONE")
	get_tree().quit()
