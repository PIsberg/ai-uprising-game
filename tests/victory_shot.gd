extends Node
## Dev probe: captures the victory cutscene's key beats to PNG so framing and
## the dawn-brightening dead-brain shot can be judged by eye. Run WINDOWED
## (headless renders black):
##   godot --path . res://tests/victory_shot.tscn --quit-after 400

func _ready() -> void:
	var cs: Node = (load("res://scenes/cutscene/victory_cutscene.tscn") as PackedScene).instantiate()
	add_child(cs)
	var idx := 0
	# Beat 1 (dead brain establishing) ~2s, beat 2 (orbit + spark) ~7s,
	# beat 3 (dawn breaking, mid-tween) ~12.5s, beat 4 (final wide/title) ~17.5s.
	for t in [2.0, 7.0, 12.5, 17.5]:
		while _t < t:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_frame("victory_%d.png" % idx)
		idx += 1
	get_tree().quit()

var _t := 0.0
func _process(delta: float) -> void:
	_t += delta

func _frame(fname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/" + fname)
	print("SAVED ", fname, " at t=", String.num(_t, 1))
