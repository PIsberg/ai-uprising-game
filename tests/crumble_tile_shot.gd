extends Node3D
## Windowed visual check for a level's crumbling slabs (Vulcan Forge's by
## default): the line from the deck at its start at eye height, then a slab
## mid-crack beside its neighbours, then the gap where one has dropped.
## Headless gives black frames.
##   godot --path . res://tests/crumble_tile_shot.tscn -- --out=<abs dir> [--level=<id>]

var _out_dir := ""
var _level := "lava_world"

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://crumble_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
		elif a.begins_with("--level="):
			_level = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/crumble_%s_%s.png" % [_out_dir, _level, name])
	print("SHOT ", name)

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % _level) as PackedScene).instantiate()
	add_child(lvl)
	for i in 30:
		await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(e as Node3D).visible = false
	var line: Dictionary = LevelDefs.get_def(_level)["crumble_tiles"][0]
	var from: Vector3 = line["from"]
	var to: Vector3 = line["to"]
	var dir := (to - from)
	dir.y = 0.0
	dir = dir.normalized()
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	player.get_node("Damageable").set("invulnerable", true)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = Vector3(60, 10, 60)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 75.0
	cam.global_position = from - dir * 1.5 + Vector3.UP * 1.7
	cam.look_at(to + Vector3.UP * 0.4)
	for i in 10:
		await get_tree().physics_frame
	await _shot("line")
	var tiles := lvl.find_children("*", "CrumbleTile", true, false)
	var t0 := tiles[1] as CrumbleTile
	player.global_position = t0.global_position
	while t0.phase != CrumbleTile.Phase.CRACKING or t0._t < CrumbleTile.HOLD * 0.8:
		await get_tree().physics_frame
	player.global_position = Vector3(60, 10, 60)
	cam.global_position = t0.global_position - dir * 3.5 + Vector3(dir.z, 0, -dir.x) * 2.0 + Vector3.UP * 2.2
	cam.look_at(t0.global_position)
	await _shot("cracking")
	while t0.phase != CrumbleTile.Phase.GONE or t0._t < 0.8:
		await get_tree().physics_frame
	await _shot("dropped")
	print("RESULT PASS")
	get_tree().quit()
