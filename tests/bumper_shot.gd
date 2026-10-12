extends Node3D
## Windowed visual check for a level's bumpers (the Neon Arcade's first, by
## default): the bumper from behind with its chevrons, the conduit it throws
## over and its landing ring; then a robot mid-throw over the conduit.
## Headless gives black frames.
##   godot --path . res://tests/bumper_shot.tscn -- --out=<abs dir> [--level=<id>]

var _out_dir := ""
var _level := "neon"

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://bumper_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
		elif a.begins_with("--level="):
			_level = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/bumper_%s_%s.png" % [_out_dir, _level, name])
	print("SHOT ", name)

## Keep the level's own robots out of the frame and out of the fight.
func _still(keep: Node) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == keep:
			continue
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(e as Node3D).visible = false

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % _level) as PackedScene).instantiate()
	add_child(lvl)
	for i in 30:
		await get_tree().process_frame
	_still(null)
	var bp := lvl.find_children("*", "Bumper", true, false)[0] as Bumper
	var player := get_tree().get_first_node_in_group("player") as Node3D
	player.global_position = bp.global_position + Vector3(0, 0, 40)
	player.get_node("Damageable").set("invulnerable", true)
	var dir := (bp.to - bp.global_position)
	dir.y = 0.0
	dir = dir.normalized()
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 70.0
	cam.global_position = bp.global_position - dir * 4.5 + Vector3.UP * 2.6
	cam.look_at(bp.to + Vector3.UP * 0.5)
	for i in 10:
		await get_tree().physics_frame
	await _shot("aim")
	# A robot steps on it: catch it at the top of its arc.
	var bot: EnemyBase = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	bot.position = bp.global_position + Vector3.UP * 0.05
	lvl.add_child(bot)
	var top := 0.0
	var t := 0.0
	while t < 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		_still(bot)
		if bot.is_launched():
			top = maxf(top, bot.global_position.y)
			if bot.global_position.y < top - 0.05:
				break
	cam.global_position = bp.global_position - dir * 2.0 + Vector3.UP * 1.2 + dir.cross(Vector3.UP) * 7.0
	cam.look_at(bot.global_position)
	await _shot("robot_thrown")
	print("RESULT PASS")
	get_tree().quit()
