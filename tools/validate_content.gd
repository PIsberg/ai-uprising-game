extends SceneTree
## Headless validation for new content. Loads scripts (catches parse errors),
## loads resources/scenes, and instantiates scenes INTO the tree so _ready runs.
## Run: godot --headless --path . -s tools/validate_content.gd

func _initialize() -> void:
	var ok := true

	# Scripts — load() fails on a parse error.
	var scripts := [
		"res://scripts/weapons/weapon.gd",
		"res://scripts/enemies/enemy_vacuum.gd",
		"res://scripts/enemies/enemy_reaper.gd",
		"res://scripts/enemies/enemy_hunter.gd",
		"res://scripts/enemies/enemy_sentinel.gd",
		"res://scripts/enemies/enemy_mauler.gd",
		"res://scripts/levels/level_builder.gd",
		"res://scripts/cutscene/level_briefing.gd",
		"res://scripts/cutscene/level_comic_briefing.gd",
		"res://scripts/cutscene/uprising_reveal.gd",
		"res://scripts/autoload/game_state.gd",
	]
	for p in scripts:
		if load(p) == null:
			push_error("SCRIPT PARSE FAILED: " + p); ok = false
		else:
			print("OK script: ", p)

	# Resources.
	for p in ["res://assets/weapons/sniper_data.tres", "res://assets/weapons/magnum_data.tres"]:
		if load(p) == null:
			push_error("RES LOAD FAILED: " + p); ok = false
		else:
			print("OK res: ", p)

	# Scenes — instantiate into the tree so _ready() (and procedural build) runs.
	var scenes := [
		"res://scenes/weapons/sniper.tscn",
		"res://scenes/weapons/magnum.tscn",
		"res://scenes/enemies/vacuum.tscn",
		"res://scenes/enemies/reaper.tscn",
		"res://scenes/enemies/hunter.tscn",
		"res://scenes/enemies/sentinel.tscn",
		"res://scenes/enemies/mauler.tscn",
		"res://scenes/player/player.tscn",
		"res://scenes/levels/level_sublevel.tscn",
		"res://scenes/levels/level_crucible.tscn",
		"res://scenes/levels/level_frostbreak.tscn",
		"res://scenes/levels/level_neon.tscn",
		"res://scenes/cutscene/uprising_reveal.tscn",
		"res://scenes/cutscene/level_comic_briefing.tscn",
	]
	for p in scenes:
		var ps = load(p)
		if ps == null:
			push_error("SCENE LOAD FAILED: " + p); ok = false
			continue
		var inst = ps.instantiate()
		if inst == null:
			push_error("INSTANTIATE FAILED: " + p); ok = false
			continue
		root.add_child(inst)   # triggers _ready (and vacuum _build_model)
		print("OK scene _ready: ", p, " -> ", inst.name)
		inst.queue_free()

	print("VALIDATION RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
