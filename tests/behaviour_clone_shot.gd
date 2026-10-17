extends Node3D
## Windowed visual check for the BEHAVIOUR CLONE in a real level (GPT Foundry
## by default): a scripted player walks and fires along a line; after the
## clone's training it is shot from behind and to the side while replaying,
## its red laser on, then mid-volley (tracers). Headless gives black frames.
##   godot --path . res://tests/behaviour_clone_shot.tscn -- --out=<abs dir> [--level=<id>]

var _out_dir := ""
var _level := "gpt"

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://behaviour_clone_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
		elif a.begins_with("--level="):
			_level = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/behaviour_clone_%s_%s.png" % [_out_dir, _level, name])
	print("SHOT ", name)

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % _level) as PackedScene).instantiate()
	add_child(lvl)
	for i in 30:
		await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(e as Node3D).visible = false
	GameState.current_state = GameState.State.PLAYING
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	player.get_node("Damageable").set("invulnerable", true)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var start: Vector3 = LevelDefs.get_def(_level).get("spawn", Vector3.ZERO)
	start.y = 0.05
	player.global_position = start
	var head := player.get_node("Head") as Node3D
	var dir := (Vector3.ZERO - start)
	dir.y = 0.0
	dir = dir.normalized()
	head.global_rotation = Vector3(0, atan2(-dir.x, -dir.z), 0)
	(head.get_node("Camera3D") as Node3D).rotation = Vector3.ZERO
	var clone := BehaviourClone.new()
	add_child(clone)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 70.0
	var side := Vector3(dir.z, 0, -dir.x)
	var shoot_t := 0.0
	for i in int((BehaviourClone.TRAIN_TIME + 2.0) * Engine.physics_ticks_per_second):
		player.global_position += dir * (2.0 / Engine.physics_ticks_per_second)
		shoot_t -= 1.0 / Engine.physics_ticks_per_second
		if shoot_t <= 0.0:
			shoot_t = 0.25
			GameState.stat_shots += 1
		cam.global_position = clone.global_position - dir * 2.5 + side * 2.5 + Vector3.UP * 2.0
		cam.look_at(clone.global_position + dir * 3.0 + Vector3.UP * 1.3)
		await get_tree().physics_frame
	await _shot("replay")
	var before := clone.shots_fired
	while clone.shots_fired == before:
		await get_tree().physics_frame
	await _shot("volley")
	print("RESULT PASS")
	get_tree().quit()
