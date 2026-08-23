extends Node
## Dev probe: verifies GameState.advance_level(), once the campaign is exhausted
## (i.e. the ARCHON finale was just cleared), routes to the victory cutscene
## instead of dropping straight to the main menu — the same call the HUD's
## "Finish" button makes (hud.gd _on_continue_pressed -> advance_level).
##
## It asserts the DESTINATION, not the mechanism: advance_level deliberately hops
## through the loading screen on the way (building the cutscene's 3D dawn set
## synchronously froze the main thread on a black frame), so the cutscene is not
## the current scene on the next frame. The old version of this probe sampled
## once at 0.3s, caught the loading screen mid-hop, and had been reporting a
## false FAIL ever since that anti-freeze fix landed — see issue #59.
##   godot --headless --path . --audio-driver Dummy res://tests/victory_probe.tscn

func _ready() -> void:
	var tree := get_tree()
	var camp: Array = GameState.campaign()
	var last := camp.size() - 1
	GameState.current_level_path = camp[last]
	GameState.level_index = last
	GameState.max_level_reached = last
	print("CAMPAIGN_SIZE=", camp.size())
	print("HAS_NEXT_LEVEL=", GameState.has_next_level())
	if GameState.has_next_level():
		print("FAIL still has a next level at the last index")
		print("RESULT FAIL")
		tree.quit(1)
		return

	# The watcher lives under /root, not under this probe: advance_level calls
	# change_scene_to_file, which frees this scene root out from under us.
	var watch := Node.new()
	watch.name = "VictoryWatch"
	watch.set_script(load("res://tests/victory_watch.gd"))
	tree.root.add_child.call_deferred(watch)

	# Deferred: the real call site (HUD's "Finish" button) fires well after the
	# tree has settled; calling it straight from this probe's own _ready (still
	# mid add-to-tree) trips Godot's "parent busy" guard on the scene swap.
	GameState.advance_level.call_deferred()
