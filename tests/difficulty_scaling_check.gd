extends Node3D
## Headless check: how many spawners survive apply_level_scaling per difficulty.
## Builds a representative level (10 immediate + 6 trigger + 1 boss) and runs the
## real GameState._scale_enemy_count via apply_level_scaling. Run as a SCENE (so
## autoloads exist): godot --headless --path . tests/difficulty_scaling_check.tscn

func _ready() -> void:
	var boss_scene := load("res://scenes/enemies/archon.tscn")
	var grunt_scene := load("res://scenes/enemies/drone.tscn")     # common
	var special_scene := load("res://scenes/enemies/spider.tscn")  # rare (must survive Easy)

	for diff in [GameState.Difficulty.EASY, GameState.Difficulty.NORMAL, GameState.Difficulty.HARD]:
		GameState.difficulty = diff
		var level := Node3D.new()
		add_child(level)
		for i in 12:  # common grunts (trigger reinforcements) — culled first
			var s := EnemySpawner.new()
			s.enemy_scene = grunt_scene
			s.spawn_on_ready = false
			s.trigger_radius = 12.0
			level.add_child(s)
		for i in 2:  # rare specials (trigger) — should be protected on Easy
			var s := EnemySpawner.new()
			s.enemy_scene = special_scene
			s.spawn_on_ready = false
			s.trigger_radius = 14.0
			level.add_child(s)
		var b := EnemySpawner.new()  # 1 boss
		b.enemy_scene = boss_scene
		b.spawn_on_ready = false
		level.add_child(b)

		GameState.apply_level_scaling(level)
		await get_tree().process_frame
		await get_tree().process_frame  # let queue_free settle

		var alive := 0
		var spiders := 0
		for c in level.get_children():
			if c is EnemySpawner and is_instance_valid(c):
				alive += 1
				if "spider" in (c.enemy_scene.resource_path if c.enemy_scene else ""):
					spiders += 1
		print("%s: total=15 -> survived=%d  spiders_kept=%d/2" % [
			GameState.difficulty_label(), alive, spiders])
		level.queue_free()
		await get_tree().process_frame
	get_tree().quit()
