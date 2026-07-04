extends Node
## Dev probe: verifies GameState.advance_level(), once the campaign is
## exhausted (i.e. the ARCHON finale was just cleared), routes to the victory
## cutscene instead of dropping straight to the main menu — the same call the
## HUD's "Finish" button makes (hud.gd _on_continue_pressed -> advance_level).
## Run headless: godot --headless --path . res://tests/victory_probe.tscn --quit-after 90
##
## The assertion runs from a Callable bound only to `tree`/GameState (not
## `self`) because advance_level() calls change_scene_to_file(), which frees
## this probe's own scene root once the swap lands.

func _ready() -> void:
	var tree := get_tree()
	var camp: Array = GameState.campaign()
	var last := camp.size() - 1
	GameState.current_level_path = camp[last]
	GameState.level_index = last
	GameState.max_level_reached = last
	print("CAMPAIGN_SIZE=", camp.size())
	print("HAS_NEXT_LEVEL=", GameState.has_next_level())
	# Deferred: the real call site (HUD's "Finish" button) fires well after the
	# tree has settled; calling it straight from this probe's own _ready (still
	# mid add-to-tree) trips Godot's "parent busy" guard on the scene swap.
	GameState.advance_level.call_deferred()
	tree.create_timer(0.3).timeout.connect(func() -> void:
		var cur := tree.current_scene
		var cls := cur.get_class() if cur else "null"
		var script_path: String = (cur.get_script().resource_path if cur and cur.get_script() else "none")
		print("CURRENT_SCENE_CLASS=", cls)
		print("CURRENT_SCENE_SCRIPT=", script_path)
		print("GAME_STATE=", GameState.current_state)
		print("SAVE_EXISTS=", GameState.has_save())
		var ok := script_path.ends_with("victory_cutscene.gd")
		print("RESULT ", "PASS" if ok else "FAIL")
		tree.quit()
	)
