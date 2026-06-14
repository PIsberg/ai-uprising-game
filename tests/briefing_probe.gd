extends Node
## Dev probe: runs the REAL level_briefing for a level that introduces a tall new
## hostile (titan), capturing frames so the orbit showcase + head framing can be
## eyeballed and the spawn logic validated. Saves user://briefing_*.png.
## Run WINDOWED (headless renders black):
##   godot --path . res://tests/briefing_probe.tscn

func _ready() -> void:
	GameState.current_level_path = "res://scenes/levels/level_titan.tscn"
	GameState.seen_enemy_types = {} # fresh run: every type is "new"
	var brief: Node = (load("res://scenes/cutscene/level_briefing.tscn") as PackedScene).instantiate()
	add_child(brief)
	await get_tree().process_frame
	await get_tree().process_frame
	print("ROBOTS_SHOWN=", brief._shown.size())
	for s in brief._shown:
		print("  ", s["type"], " center=", s["center"], " radius=", String.num(s["radius"], 2))
	# Capture across the establishing shot (4.5s) and the per-robot orbit shots
	# (5s each) so each new hostile's showcase is sampled.
	var idx := 0
	for t in [2.0, 7.0, 12.0, 17.0, 21.0]:
		while _t < t:
			await get_tree().process_frame
		_frame("briefing_%d.png" % idx)
		idx += 1
	get_tree().quit()

var _t := 0.0
func _process(delta: float) -> void:
	_t += delta

func _frame(fname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/" + fname)
	print("SAVED ", fname, " at t=", String.num(_t, 1))
